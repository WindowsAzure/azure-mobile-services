﻿// ----------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// ----------------------------------------------------------------------------

using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;

namespace Microsoft.WindowsAzure.MobileServices.Sync
{
    /// <summary>
    /// Responsible for executing a batch of operations from queue until bookmark is found
    /// </summary>
    internal class PushAction: SyncAction
    {
        private BookmarkOperation bookmark;
        private IMobileServiceSyncHandler syncHandler;
        private MobileServiceJsonSerializerSettings serializerSettings;

        public PushAction(OperationQueue operationQueue, IMobileServiceLocalStore store, IMobileServiceSyncHandler syncHandler, MobileServiceJsonSerializerSettings  serializerSettings, CancellationToken cancellationToken, BookmarkOperation bookmark): base(operationQueue, store, cancellationToken)
        {
            this.syncHandler = syncHandler;
            this.bookmark = bookmark;
            this.serializerSettings = serializerSettings;
        }        

        public override async Task ExecuteAsync()
        {
            var batch = new OperationBatch(this.syncHandler, this.Store);

            // when cancellation is requested, abort the batch
            this.CancellationToken.Register(() => batch.Abort(MobileServicePushStatus.CancelledByToken));

            MobileServiceTableOperation operation = this.OperationQueue.Peek();

            // keep taking out operations and executing them until queue is empty or operation finds the bookmark or batch is aborted 
            while (operation != null && operation != this.bookmark)
            {
                try
                {
                    await this.ExecuteOperationAsync(operation, batch);
                }
                catch (Exception ex)
                {
                    batch.HandlerErrors.Add(ex);
                }

                if (batch.IsAborted)
                {
                    break;
                }

                // we successfuly executed an operation so remove it from queue
                await this.OperationQueue.DequeueAsync();

                // get next operation
                operation = this.OperationQueue.Peek();
            }

            // if sync operation found the bookmark in operation queue, remove it
            if (operation == this.bookmark)
            {
                await this.OperationQueue.DequeueAsync();
            }

            MobileServicePushStatus batchStatus = batch.Status.GetValueOrDefault(MobileServicePushStatus.Complete);
            IEnumerable<MobileServiceTableOperationError> syncErrors = Enumerable.Empty<MobileServiceTableOperationError>();
            try
            {
                syncErrors = await batch.LoadSyncErrorsAsync(this.serializerSettings);
            }
            catch (Exception ex)
            {

                batch.HandlerErrors.Add(new MobileServiceSyncStoreException(Resources.SyncStore_FailedToLoadError, ex));
            }

            var result = new MobileServicePushCompletionResult(syncErrors, batchStatus);

            if (syncErrors != null)
            {
                try
                {
                    await batch.SyncHandler.OnPushCompleteAsync(result);

                    // now that we've successfully given the errors to user, we can delete them from store
                    await batch.DeleteErrorsAsync(syncErrors);
                }
                catch (Exception ex)
                {
                    batch.HandlerErrors.Add(ex);
                }
            }

            if (batch.IsAborted || batch.HasErrors(syncErrors))
            {
                List<MobileServiceTableOperationError> unhandledSyncErrors = syncErrors.Where(e=>!e.Handled).ToList();
                Exception inner = batch.HandlerErrors.Count == 1 ? batch.HandlerErrors[0] : batch.HandlerErrors.Any() ? new AggregateException(batch.HandlerErrors) : null;

                // create a new result with only unhandled errors
                result = new MobileServicePushCompletionResult(unhandledSyncErrors, batchStatus);
                this.TaskSource.TrySetException(new MobileServicePushFailedException(result, inner));
            }
            else
            {
                this.TaskSource.SetResult(0);
            }
        }

        private async Task ExecuteOperationAsync(MobileServiceTableOperation operation, OperationBatch batch)
        {
            if (operation is BookmarkOperation)
            {
                return; // nothing to execute in a bookmark
            }

            using (await this.OperationQueue.LockItemAsync(operation.ItemId, this.CancellationToken))
            {
                if (operation.IsCancelled || this.CancellationToken.IsCancellationRequested)
                {
                    return;
                }

                Exception error = null;

                await LoadOperationItem(operation, batch);

                if (this.CancellationToken.IsCancellationRequested)
                {
                    return;
                }

                try
                {
                    await batch.SyncHandler.ExecuteTableOperationAsync(operation);
                }
                catch (Exception ex)
                {
                    if (AbortBatch(batch, ex))
                    {
                        // there is no error to save in sync error and no result to capture
                        // this operation will be executed again next time the push happens
                        return;
                    }

                    error = ex;
                }

                if (error == null)
                {
                    JObject obj = operation.Result as JObject;  // store can only upsert jobjects
                    if (obj != null && operation.WriteResultToStore)
                    {
                        obj = MobileServiceSyncTable.RemoveSystemPropertiesKeepVersion(obj);
                        try
                        {
                            await operation.Table.MobileServiceClient.SyncContext.Store.UpsertAsync(operation.TableName, obj);
                        }
                        catch (Exception ex)
                        {
                            batch.Abort(MobileServicePushStatus.CancelledBySyncStoreError);
                            throw new MobileServiceSyncStoreException(Resources.SyncStore_FailedToUpsertItem, ex);
                        }
                    }
                }
                else
                {
                    HttpStatusCode? status = null;
                    Tuple<string, JToken> content = null;
                    // if the operation was not successful and we have an error that can give us jtoken result, then take it.
                    if (error is MobileServiceInvalidOperationException)
                    {
                        var msIOEx = (MobileServiceInvalidOperationException)error;
                        content = await operation.Table.ParseContent(msIOEx.Response);
                        if (msIOEx.Response != null)
                        {
                            status = msIOEx.Response.StatusCode;
                        }
                    }

                    string rawResult = content != null ? content.Item1 : null;
                    JToken result = content != null ? content.Item2 : null;
                    var syncError = new MobileServiceTableOperationError(status, operation.Kind, operation.TableName, operation.Item, rawResult, result);
                    await batch.AddSyncErrorAsync(syncError);
                }
            }
        }

        private static async Task LoadOperationItem(MobileServiceTableOperation operation, OperationBatch batch)
        {
            // only read the item from store if it is not in the operation already
            if (operation.Item == null)
            {
                try
                {
                    operation.Item = await batch.Store.LookupAsync(operation.TableName, operation.ItemId) as JObject;
                }
                catch (Exception ex)
                {
                    batch.Abort(MobileServicePushStatus.CancelledBySyncStoreError);
                    throw new MobileServiceSyncStoreException(Resources.SyncStore_FailedToReadItem, ex);
                }
            }
        }

        private bool AbortBatch(OperationBatch batch, Exception ex)
        {
            if (ex.IsNetworkError())
            {                
                batch.Abort(MobileServicePushStatus.CancelledByNetworkError);
            }
            else if (ex.IsAuthenticationError())
            {
                batch.Abort(MobileServicePushStatus.CancelledByAuthenticationError);
            }
            else
            {
                return false; // not a known exception that should abort the batch
            }

            return true;
        }
    }
}