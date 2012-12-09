/*
    MongoDB DataProvider Sitecore module
    Copyright (C) 2012  Robin Hermanussen

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using Sitecore.Data.DataProviders;
using Sitecore.Data;
using Sitecore.Collections;
using MongoDB.Driver;
using MongoDataProvider.Data;
using MongoDB.Driver.Builders;
using Sitecore;
using Sitecore.Caching;
using Sitecore.Configuration;

namespace MongoDataProvider
{
    /// <summary>
    /// Provides item data from a Mongo database (www.mongodb.org).
    /// Configure this through MongoDataProvider.config.
    /// </summary>
    public class MongoDataProvider : DataProvider
    {
        /// <summary>
        /// The ID of the item that is the parent of all data in this provider.
        /// </summary>
        private ID JoinParentId { get; set; }

        private MongoServer Server { get; set; }

        private MongoDatabase Db { get; set; }

        private MongoCollection<Item> Items { get; set; }

        /// <summary>
        /// If true, MongoDB ensures that data is written to disk when inserting/updating (slower, but more reliable).
        /// </summary>
        private SafeMode SafeMode { get; set; }
        
        public MongoDataProvider(string joinParentId, string mongoConnectionString, string databaseName, string safeMode)
        {
            bool parsedSafeMode;
            SafeMode = SafeMode.Create(bool.TryParse(safeMode, out parsedSafeMode) ? parsedSafeMode : false);

            JoinParentId = new ID(joinParentId);

            Server = MongoServer.Create(mongoConnectionString);

            Db = Server.GetDatabase(databaseName);

            Items = Db.GetCollection<Item>("items", SafeMode);

            Items.EnsureIndex(IndexKeys.Ascending(new[] { "ParentID" }));
            Items.EnsureIndex(IndexKeys.Ascending(new[] { "TemplateID" }));            

            EnsureNotEmpty();
        }

        /// <summary>
        /// Prefills the database with a root item, if it is not available.
        /// </summary>
        private void EnsureNotEmpty()
        {
            if (Items.Count() > 0)
            {
                return;
            }
            
            // Create a root item and insert it
            Item rootItem = new Item()
                {
                    _id = new ID("{11111111-1111-1111-1111-111111111111}").ToGuid(),
                    Name = "sitecore",
                    TemplateID = new ID("{C6576836-910C-4A3D-BA03-C277DBD3B827}").ToGuid()
                };
            Items.Insert(rootItem, SafeMode);
            AddVersion(
                new ItemDefinition(new ID(rootItem._id), rootItem.Name, new ID(rootItem.TemplateID), ID.Null),
                new VersionUri(Sitecore.Data.Managers.LanguageManager.DefaultLanguage, Sitecore.Data.Version.First),
                null);
        }

        private Cache prefetchCache { get; set; }
        protected readonly object PrefetchCacheLock = new object();
        private long prefetchCacheSize = Settings.Caching.DefaultDataCacheSize;

        protected Cache PrefetchCache
        {
            get
            {
                if (prefetchCache != null)
                {
                    return this.prefetchCache;
                }
                lock (PrefetchCacheLock)
                {
                    if (prefetchCache == null)
                    {
                        string name = "MongoDataProvider - Prefetch data";
                        Cache namedInstance = Cache.GetNamedInstance(name, prefetchCacheSize);
                        if (CacheOptions.DisableAll)
                        {
                            namedInstance.Enabled = false;
                        }
                        this.prefetchCache = namedInstance;
                    }
                    return this.prefetchCache;
                }
            }
        }

        /// <summary>
        /// Returns a definition containing the id, name, template id, branch id and parent id of the Item that corresponds with the itemId parameter.
        /// </summary>
        /// <param name="itemId">The item id to search for</param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override ItemDefinition GetItemDefinition(ID itemId, CallContext context)
        {
            PrefetchData prefetchData = GetPrefetchData(itemId);
            if (prefetchData == null)
            {
                return null;
            }
            return prefetchData.ItemDefinition;
        }

        private PrefetchData GetPrefetchData(ID itemId)
        {
            PrefetchData data = this.PrefetchCache[itemId] as PrefetchData;
            if (data != null)
            {
                if (!data.ItemDefinition.IsEmpty)
                {
                    return data;
                }
                return null;
            }
            ItemInfo result = Items.FindOneByIdAs<ItemInfo>(itemId.ToGuid());

            if (result != null)
            {
                data = new PrefetchData(new ItemDefinition(itemId, result.Name, new ID(result.TemplateID), new ID(result.BranchID)), new ID(result.ParentID));
                this.PrefetchCache.Add(itemId, data, data.GetDataLength());
                return data;
            }

            return null;
        }

        /// <summary>
        /// Get a list of all available versions in different languages.
        /// </summary>
        /// <param name="itemDefinition">Used to identify the particular item</param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override VersionUriList GetItemVersions(ItemDefinition itemDefinition, CallContext context)
        {
            Item result = Items.FindOneById(itemDefinition.ID.ToGuid());
            if (result != null && result.FieldValues != null)
            {
                VersionUriList versions = new VersionUriList();
                var versionsList = new List<VersionUri>();
                foreach (FieldValueId fieldValueId in result.FieldValues.Keys.Where(fv => fv.Version.HasValue && fv.Language != null))
                {
                    if (versionsList.Where(ver => fieldValueId.Matches(ver)).Count() == 0)
                    {
                        VersionUri newVersionUri = new VersionUri(
                            Sitecore.Data.Managers.LanguageManager.GetLanguage(fieldValueId.Language),
                            new Sitecore.Data.Version(fieldValueId.Version.Value));
                        versionsList.Add(newVersionUri);
                    }
                }
                foreach (var version in versionsList)
                {
                    versions.Add(version);
                }
                return versions;
            }
            return null;
        }

        /// <summary>
        /// Get a list of all the item's fields and their values.
        /// </summary>
        /// <param name="itemDefinition">Used to identify the particular item</param>
        /// <param name="versionUri">The language and version of the item to get field values for</param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override FieldList GetItemFields(ItemDefinition itemDefinition, VersionUri versionUri, CallContext context)
        {
            Item result = Items.FindOneById(itemDefinition.ID.ToGuid());
            if (result != null && result.FieldValues != null)
            {
                FieldList fields = new FieldList();
                foreach (KeyValuePair<FieldValueId, string> fieldValue in result.FieldValues.Where(fv => fv.Key.Matches(versionUri)))
                {
                    fields.Add(new ID(fieldValue.Key.FieldId), fieldValue.Value);
                }
                return fields;
            }
            return null;
        }

        /// <summary>
        /// Determines what items are children of the item and returns a list of their IDs.
        /// </summary>
        /// <param name="itemDefinition">Used to identify the particular item</param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override IDList GetChildIDs(ItemDefinition itemDefinition, CallContext context)
        {
            QueryComplete query = Query.EQ("ParentID",
                itemDefinition.ID == JoinParentId
                    ? Guid.Empty
                    : itemDefinition.ID.ToGuid());
            return IDList.Build(Items.FindAs<ItemBase>(query)
                .Select(it => new ID(it._id)).ToArray());
        }

        /// <summary>
        /// Get the ID of the parent of an item. 
        /// </summary>
        /// <param name="itemDefinition">Used to identify the particular item</param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override ID GetParentID(ItemDefinition itemDefinition, CallContext context)
        {
            ItemBase result = Items.FindOneByIdAs<ItemBase>(itemDefinition.ID.ToGuid());
            return result != null
                ? (result.ParentID != Guid.Empty ? new ID(result.ParentID) : JoinParentId)
                : null;
        }

        /// <summary>
        /// Create a new item as a child of another item.
        /// Note that this does not create any versions or field values.
        /// </summary>
        /// <param name="itemID">The item ID (not the parent's)</param>
        /// <param name="itemName">The name of the new item</param>
        /// <param name="templateID">The ID of the content item that represents its template</param>
        /// <param name="parent">The parent item's definition</param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override bool CreateItem(ID itemID, string itemName, ID templateID, ItemDefinition parent, CallContext context)
        {
            ItemBase current = Items.FindOneByIdAs<ItemBase>(itemID.ToGuid());
            if (current != null)
            {
                // item already exists
                return false;
            }

            if (parent != null)
            {
                ItemBase parentItem = Items.FindOneByIdAs<ItemBase>(parent.ID.ToGuid());
                if (parentItem == null)
                {
                    // parent item does not exist in this provider
                    return false;
                }
            }

            Items.Save(new ItemInfo()
                {
                    _id = itemID.ToGuid(),
                    Name = itemName,
                    TemplateID = templateID.ToGuid(),
                    ParentID = parent != null ? parent.ID.ToGuid() : Guid.Empty
                }, SafeMode);

            return true;
        }

        /// <summary>
        /// Creates a new version for a content item in a particular language.
        /// </summary>
        /// <param name="itemDefinition">Used to identify the particular item</param>
        /// <param name="baseVersion">The version to copy off of</param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override int AddVersion(ItemDefinition itemDefinition, VersionUri baseVersion, CallContext context)
        {
            Item current = Items.FindOneById(itemDefinition.ID.ToGuid());
            if (current == null)
            {
                return -1;
            }

            int num = -1;

            if (baseVersion.Version != null && baseVersion.Version.Number > 0)
            {
                // copy version
                var currentFieldValues = current.FieldValues.Where(fv => fv.Key.Matches(baseVersion)).ToList();
                int? maxVersionNumber = currentFieldValues.Max(fv => fv.Key.Version);
                num = maxVersionNumber.HasValue && maxVersionNumber > 0 ? maxVersionNumber.Value + 1 : -1;

                if(num > 0)
                {
                    foreach (KeyValuePair<FieldValueId, string> fieldValue in currentFieldValues)
                    {
                        current.FieldValues.Add(new FieldValueId()
                            {
                                FieldId = fieldValue.Key.FieldId,
                                Language = fieldValue.Key.Language,
                                Version = num
                            }, fieldValue.Value);
                    }
                }
            }
            if (num == -1)
            {
                num = 1;

                // add blank version
                current.FieldValues.Add(new FieldValueId()
                    {
                        FieldId = FieldIDs.Created.ToGuid(),
                        Language = baseVersion.Language.Name,
                        Version = num
                    }, string.Empty);
            }

            Items.Save(current, SafeMode);

            return num;
        }

        /// <summary>
        /// Removes an item from the database completely.
        /// </summary>
        /// <param name="itemDefinition">Used to identify the particular item</param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override bool DeleteItem(ItemDefinition itemDefinition, CallContext context)
        {
            SafeModeResult result = Items.Remove(Query.EQ("_id", itemDefinition.ID.ToGuid()), RemoveFlags.Single, SafeMode);
            return result != null && result.Ok;
        }

        /// <summary>
        /// Save changes that were made to an item to the database.
        /// </summary>
        /// <param name="itemDefinition">Used to identify the particular item</param>
        /// <param name="changes">A holder object that keeps track of the changes</param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override bool SaveItem(ItemDefinition itemDefinition, Sitecore.Data.Items.ItemChanges changes, CallContext context)
        {
            Item current = Items.FindOneById(itemDefinition.ID.ToGuid());
            if (current == null)
            {
                return false;
            }

            if (changes.HasPropertiesChanged)
            {
                current.Name = StringUtil.GetString(changes.GetPropertyValue("name"), itemDefinition.Name);

                ID templateId = MainUtil.GetObject(changes.GetPropertyValue("templateid"), itemDefinition.TemplateID) as ID;
                current.TemplateID = templateId != ID.Null ? templateId.ToGuid() : Guid.Empty;

                ID branchId = MainUtil.GetObject(changes.GetPropertyValue("branchid"), itemDefinition.BranchId) as ID;
                current.BranchID = branchId != ID.Null ? branchId.ToGuid() : Guid.Empty;
            }
            if (changes.HasFieldsChanged)
            {
                foreach (Sitecore.Data.Items.FieldChange change in changes.FieldChanges)
                {
                    VersionUri fieldVersionUri = new VersionUri(
                        change.Definition == null || change.Definition.IsShared ? null : change.Language,
                        change.Definition == null || change.Definition.IsUnversioned ? null : change.Version);
                    var matchingFields = current.FieldValues.Where(fv => fv.Key.Matches(fieldVersionUri) && fv.Key.FieldId.Equals(change.FieldID.ToGuid()));

                    if (change.RemoveField)
                    {
                        if(matchingFields.Count() > 0)
                        {
                            current.FieldValues.Remove(matchingFields.First().Key);
                        }
                    }
                    else
                    {
                        if (matchingFields.Count() > 0)
                        {
                            current.FieldValues[matchingFields.First().Key] = change.Value;
                        }
                        else
                        {
                            current.FieldValues.Add(new FieldValueId()
                                {
                                    FieldId = change.FieldID.ToGuid(),
                                    Language = fieldVersionUri.Language != null ? fieldVersionUri.Language.Name : null,
                                    Version = fieldVersionUri.Version != null ? fieldVersionUri.Version.Number : null as int?
                                }, change.Value);
                        }
                    }
                }

                Items.Save(current, SafeMode);
            }
            return true;
        }

        public override IdCollection GetTemplateItemIds(CallContext context)
        {
            QueryComplete query = Query.EQ("TemplateID", TemplateIDs.Template.ToGuid());
            IdCollection ids = new IdCollection();
            foreach (var id in Items.FindAs<ItemBase>(query).Select(it => new ID(it._id)))
            {
                ids.Add(id);
            }
            return ids;
        }

        public override ID GetRootID(CallContext context)
        {
            return ItemIDs.RootID;
        }

        /// <summary>
        /// Check if a blob with the ID that is passed exists in MongoDB.
        /// </summary>
        /// <param name="blobId"></param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override bool BlobStreamExists(Guid blobId, CallContext context)
        {
            return Db.GridFS.Exists(Query.EQ("filename", new MongoDB.Bson.BsonString(new ShortID(blobId).ToString())));
        }

        /// <summary>
        /// Get a blob from MongoDB with the ID that is passed.
        /// </summary>
        /// <param name="blobId"></param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override System.IO.Stream GetBlobStream(Guid blobId, CallContext context)
        {
            var gridFsFile = Db.GridFS.FindOne(Query.EQ("filename", new MongoDB.Bson.BsonString(new ShortID(blobId).ToString())));
            return gridFsFile != null && gridFsFile.Exists ? gridFsFile.OpenRead() : null;
        }

        /// <summary>
        /// Upload a file to GridFS in MongoDB.
        /// </summary>
        /// <param name="stream"></param>
        /// <param name="blobId"></param>
        /// <param name="context"></param>
        /// <returns></returns>
        public override bool SetBlobStream(System.IO.Stream stream, Guid blobId, CallContext context)
        {
            var result = Db.GridFS.Upload(
                stream,
                new ShortID(blobId).ToString());
            return result != null;
        }
    }
}
