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
using MongoDB.Bson.Serialization.Attributes;
using MongoDB.Bson.Serialization.Options;

namespace MongoDataProvider.Data
{
    public class Item : ItemInfo
    {
        private Dictionary<FieldValueId, string> fieldValues;

        [BsonDictionaryOptions(DictionaryRepresentation.ArrayOfDocuments)]
        public Dictionary<FieldValueId, string> FieldValues
        {
            get
            {
                return fieldValues ?? (fieldValues = new Dictionary<FieldValueId,string>());
            }
            set
            {
                fieldValues = value;
            }
        }
    }
}
