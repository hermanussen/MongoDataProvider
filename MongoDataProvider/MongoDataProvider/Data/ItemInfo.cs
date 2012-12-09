﻿/*
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

namespace MongoDataProvider.Data
{
    [BsonIgnoreExtraElements]
    public class ItemInfo : ItemBase
    {
        [BsonRequired]
        public string Name { get; set; }

        [BsonRequired]
        public Guid TemplateID { get; set; }

        public Guid BranchID { get; set; }

        public override string ToString()
        {
            return string.Format("{0} ({1})", Name, _id);
        }
    }
}
