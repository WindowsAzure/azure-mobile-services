/*
Copyright (c) Microsoft Open Technologies, Inc.
All Rights Reserved
Apache 2.0 License
 
   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at
 
     http://www.apache.org/licenses/LICENSE-2.0
 
   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
 
See the Apache Version 2.0 License for specific language governing permissions and limitations under the License.
 */
package com.microsoft.windowsazure.mobileservices.table.sync.operations;

import com.google.gson.JsonObject;
import com.microsoft.windowsazure.mobileservices.table.sync.localstore.MobileServiceLocalStore;

public class LocalTableOperationProcessor implements TableOperationVisitor<Void> {
	MobileServiceLocalStore mStore;

	JsonObject mItem;

	String mItemBackupTable;

	public LocalTableOperationProcessor(MobileServiceLocalStore store, JsonObject item, String itemBackupTable) {
		this.mStore = store;
		this.mItem = item;
		this.mItemBackupTable = itemBackupTable;
	}

	@Override
	public Void visit(InsertOperation operation) throws Throwable {
		this.mStore.upsert(operation.getTableName(), this.mItem);
		return null;
	}

	@Override
	public Void visit(UpdateOperation operation) throws Throwable {
		this.mStore.upsert(operation.getTableName(), this.mItem);
		return null;
	}

	@Override
	public Void visit(DeleteOperation operation) throws Throwable {
		JsonObject backedUpItem = this.mStore.lookup(operation.getTableName(), operation.getItemId());

		// '/' is a reserved character that cannot be used on string ids.
		// We use it to build a unique compound string from tableName and
		// itemId
		String tableItemId = operation.getTableName() + "/" + operation.getItemId();

		JsonObject item = new JsonObject();
		item.addProperty("id", tableItemId);
		item.addProperty("tablename", operation.getTableName());
		item.addProperty("itemid", operation.getItemId());
		item.add("clientitem", backedUpItem);

		this.mStore.upsert(this.mItemBackupTable, item);
		this.mStore.delete(operation.getTableName(), operation.getItemId());

		return null;
	}

	public JsonObject getItem() {
		return this.mItem;
	}

	public void setItem(JsonObject item) {
		this.mItem = item;
	}
}