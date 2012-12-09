<%-- 
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
--%>
<%@ Page Language="C#" AutoEventWireup="true" %>
<%@ Import Namespace="System.Linq" %>
<%@ Import Namespace="Sitecore.Data" %>
<%@ Import Namespace="Sitecore.Data.DataProviders" %>
<%@ Import Namespace="Sitecore.Data.Items" %>
<%@ Import Namespace="Sitecore.Data.Fields" %>
<% Sitecore.Shell.Web.ShellPage.IsLoggedIn();%>
<%
if (! Sitecore.Context.User.IsInRole(@"sitecore\Developer")
    && ! Sitecore.Context.IsAdministrator)
{
    Response.Write("<p>You are not authorized to use this page</p>");
    Response.End();
}
%>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <title>Transfer items from a different database to the mongodb database</title>
</head>
<body>

<script runat="server">

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        if (! IsPostBack)
        {
            ddlDatabase.DataSource = new object[] { "- select database -" }.Concat(Sitecore.Configuration.Factory.GetDatabaseNames()); ;
            ddlDatabase.DataBind();
        }
    }

    public void DatabaseSelected(object sender, EventArgs e)
    {
        if (!"- select database -".Equals(ddlDatabase.SelectedValue))
        {
            Sitecore.Data.Database database = Sitecore.Configuration.Factory.GetDatabase(ddlDatabase.SelectedValue);
            Sitecore.Data.Database mongodb = Sitecore.Configuration.Factory.GetDatabase("mongodb");
            if (database != null && mongodb != null)
            {
                using (new Sitecore.SecurityModel.SecurityDisabler())
                {
                    Item item = database.GetRootItem();

                    MongoDataProvider.MongoDataProvider dataProvider = mongodb.GetDataProviders().First() as MongoDataProvider.MongoDataProvider;

                    Response.Write("<ul>");
                    Response.Flush();

                    TransferRecursive(item, dataProvider);

                    Response.Write("</ul>");
                    Response.Flush();
                }
            }
        }
    }

    /// <summary>
    /// Transfers the item and all underlying items to the mongodb database using the MongoDataProvider.
    /// </summary>
    /// <param name="item">The item to transfer</param>
    /// <param name="provider">The provider instance to transfer to</param>
    public void TransferRecursive(Item item, MongoDataProvider.MongoDataProvider provider)
    {
        Response.Write(string.Format("<li>Transferring {0}</li>", item.Paths.FullPath));
        Response.Flush();

        ItemDefinition parentDefinition = null;
        if(item.Parent != null)
        {
            parentDefinition = new ItemDefinition(item.Parent.ID, item.Parent.Name, item.Parent.TemplateID, item.Parent.BranchId);
        }
        
        // Create the item in MongoDB
        if (provider.CreateItem(item.ID, item.Name, item.TemplateID, parentDefinition, null))
        {
            foreach (Sitecore.Globalization.Language language in item.Languages)
            {
                using (new Sitecore.Globalization.LanguageSwitcher(language))
                {
                    Item itemInLanguage = item.Database.GetItem(item.ID);

                    if (itemInLanguage != null)
                    {
                        // Add a version
                        ItemDefinition itemDefinition = provider.GetItemDefinition(itemInLanguage.ID, null);
                        provider.AddVersion(itemDefinition, new VersionUri(language, Sitecore.Data.Version.First), null);

                        // Send the field values to the provider
                        ItemChanges changes = new ItemChanges(itemInLanguage);
                        foreach (Field field in itemInLanguage.Fields)
                        {
                            changes.FieldChanges[field.ID] = new FieldChange(field, field.Value);
                        }
                        provider.SaveItem(itemDefinition, changes, null);
                    }
                }
            }
        }

        if (!item.HasChildren)
        {
            return;
        }
        foreach (Item child in item.Children)
        {
            TransferRecursive(child, provider);
        }
    }

</script>
<form runat="server">

<p>Transfer items from this database (starts immediately): <asp:DropDownList runat="server" ID="ddlDatabase" AutoPostBack="true" OnSelectedIndexChanged="DatabaseSelected" /></p>

</form>
</body>
</html>