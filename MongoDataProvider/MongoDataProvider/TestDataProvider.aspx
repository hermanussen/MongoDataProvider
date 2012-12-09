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
<%@ Import Namespace="System.Web.UI.WebControls" %>
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
    <title>Test some actions on data providers</title>
</head>
<body>

<script runat="server">

    protected override void OnLoad(EventArgs e)
    {
        base.OnLoad(e);
        if (! IsPostBack)
        {
            List<DataProvider> dataProviders = new List<DataProvider>();
            foreach (string databaseName in Sitecore.Configuration.Factory.GetDatabaseNames())
            {
                dataProviders.AddRange(Sitecore.Configuration.Factory.GetDatabase(databaseName).GetDataProviders());
            }
            rptDataProviders.DataSource = dataProviders;
            rptDataProviders.DataBind();
        }
        else
        {
            RunTest();
        }
    }

    private void RunTest()
    {
        Response.Write(string.Format("<p>Starting test at {0}</p>", DateTime.Now));
        Response.Flush();

        foreach (RepeaterItem rptItem in rptDataProviders.Items)
        {
            CheckBox includeProvider = rptItem.FindControl("cbxIncludeProvider") as CheckBox;
            if (includeProvider.Checked)
            {
                TextBox startItemId = rptItem.FindControl("tbxStartItemId") as TextBox;
                string[] providerInfo = includeProvider.Text.Split(new[] { ':' });
                string databaseName = providerInfo[0];
                string providerTypeName = providerInfo[1].Trim();
                foreach (DataProvider dataProvider in Sitecore.Configuration.Factory.GetDatabase(databaseName).GetDataProviders().Where(provider => providerTypeName.Equals(provider.GetType().FullName)))
                {
                    CallContext callContext = new CallContext(dataProvider.Database.DataManager, rptDataProviders.Items.Count);
                    ItemDefinition startItem = dataProvider.GetItemDefinition(new Sitecore.Data.ID(startItemId.Text), callContext);
                    
                    if(startItem == null)
                    {
                        Response.Write(string.Format("<p>Startitem {0} was not found with provider {1}</p>", startItemId, includeProvider.Text));
                    }
                    else
                    {
                        bool originalValue = dataProvider.CacheOptions.DisableAll;
                        dataProvider.CacheOptions.DisableAll = true;
                        using (new DatabaseCacheDisabler())
                        {
                            RunTest(dataProvider, startItem, callContext);
                        }
                        dataProvider.CacheOptions.DisableAll = originalValue;
                    }
                }
            }
        }
    }
    
    private void RunTest(DataProvider dataProvider, ItemDefinition startItem, CallContext callContext)
    {
        Response.Write(string.Format("<p>Starting test with provider {0}: {1}</p>", dataProvider.Database.Name, dataProvider.GetType().FullName));
        Response.Flush();
        
        Dictionary<Sitecore.Data.ID, string> createdItems = new Dictionary<Sitecore.Data.ID,string>();
        Dictionary<Sitecore.Data.ID, string> createdChildItems = new Dictionary<Sitecore.Data.ID, string>();

        Response.Write("<table><tr><th>Action</th><th>Duration (in milliseconds)</th></tr>");

        Sitecore.Caching.CacheManager.ClearAllCaches();
        
        // Create a whole bunch of items
        DateTime startTime = DateTime.Now;
        for(int i = 0; i < 50; i++)
        {
            Sitecore.Data.ID id = Sitecore.Data.ID.NewID;
            string name = string.Format("Test item {0}", i);
            createdItems.Add(id, name);
            dataProvider.CreateItem(id, name, Sitecore.TemplateIDs.Folder, startItem, callContext);
            
            for(int j = 0; j < 50; j++)
            {
                Sitecore.Data.ID childId = Sitecore.Data.ID.NewID;
                string childName = string.Format("Test child item {0} {1}", i, j);
                createdChildItems.Add(childId, childName);
                dataProvider.CreateItem(childId, childName, Sitecore.TemplateIDs.Folder, new ItemDefinition(id, name, Sitecore.TemplateIDs.Folder, Sitecore.Data.ID.Null), callContext);
            }
        }
        Response.Write(string.Format("<tr><td>Create</td><td>{0}</td></tr>", DateTime.Now.Subtract(startTime).TotalMilliseconds));
        Response.Flush();

        Sitecore.Caching.CacheManager.ClearAllCaches();
        
        // Add versions to the items
        startTime = DateTime.Now;
        foreach (KeyValuePair<Sitecore.Data.ID, string> item in createdItems.Concat(createdChildItems))
        {
            ItemDefinition itemDef = new ItemDefinition(item.Key, item.Value, Sitecore.TemplateIDs.Folder, Sitecore.Data.ID.Null);
            dataProvider.AddVersion(itemDef, new VersionUri(Sitecore.Data.Managers.LanguageManager.GetLanguage("en"), new Sitecore.Data.Version(0)), callContext);
            dataProvider.AddVersion(itemDef, new VersionUri(Sitecore.Data.Managers.LanguageManager.GetLanguage("en"), new Sitecore.Data.Version(1)), callContext);
            dataProvider.AddVersion(itemDef, new VersionUri(Sitecore.Data.Managers.LanguageManager.GetLanguage("en"), new Sitecore.Data.Version(2)), callContext);
        }
        Response.Write(string.Format("<tr><td>Add versions</td><td>{0}</td></tr>", DateTime.Now.Subtract(startTime).TotalMilliseconds));
        Response.Flush();
        
        // Retrieve all items the normal way because we need them for the following actions (no performance measurement needed)
        Dictionary<Sitecore.Data.ID, Item> retrievedItems = new Dictionary<Sitecore.Data.ID,Item>();
        using (new Sitecore.SecurityModel.SecurityDisabler())
        {
            foreach (KeyValuePair<Sitecore.Data.ID, string> item in createdItems.Concat(createdChildItems))
            {
                retrievedItems.Add(item.Key, dataProvider.Database.GetItem(item.Key));
            }
        }

        Sitecore.Caching.CacheManager.ClearAllCaches();
        
        // Save the items with some changed field values
        startTime = DateTime.Now;
        foreach (KeyValuePair<Sitecore.Data.ID, string> item in createdItems.Concat(createdChildItems))
        {
            ItemDefinition itemDef = new ItemDefinition(item.Key, item.Value, Sitecore.TemplateIDs.Folder, Sitecore.Data.ID.Null);
            Sitecore.Data.Items.ItemChanges changes = new Sitecore.Data.Items.ItemChanges(retrievedItems[item.Key]);
            
            changes.FieldChanges[Sitecore.FieldIDs.Created] = new FieldChange(new Sitecore.Data.Fields.Field(Sitecore.FieldIDs.Created, retrievedItems[item.Key]), "some value");
            changes.FieldChanges[Sitecore.FieldIDs.CreatedBy] = new FieldChange(new Sitecore.Data.Fields.Field(Sitecore.FieldIDs.CreatedBy, retrievedItems[item.Key]), "some value");
            changes.FieldChanges[Sitecore.FieldIDs.Updated] = new FieldChange(new Sitecore.Data.Fields.Field(Sitecore.FieldIDs.Updated, retrievedItems[item.Key]), "some value");
            changes.FieldChanges[Sitecore.FieldIDs.UpdatedBy] = new FieldChange(new Sitecore.Data.Fields.Field(Sitecore.FieldIDs.UpdatedBy, retrievedItems[item.Key]), "some value");
            changes.FieldChanges[Sitecore.FieldIDs.Owner] = new FieldChange(new Sitecore.Data.Fields.Field(Sitecore.FieldIDs.Owner, retrievedItems[item.Key]), "some value");
            changes.FieldChanges[Sitecore.FieldIDs.Originator] = new FieldChange(new Sitecore.Data.Fields.Field(Sitecore.FieldIDs.Originator, retrievedItems[item.Key]), "some value");
            changes.FieldChanges[Sitecore.FieldIDs.DisplayName] = new FieldChange(new Sitecore.Data.Fields.Field(Sitecore.FieldIDs.DisplayName, retrievedItems[item.Key]), "some value");
            
            dataProvider.SaveItem(itemDef, changes, callContext);
        }
        Response.Write(string.Format("<tr><td>Change some field values</td><td>{0}</td></tr>", DateTime.Now.Subtract(startTime).TotalMilliseconds));
        Response.Flush();

        Sitecore.Caching.CacheManager.ClearAllCaches();
        
        // Get the parent id's for the items
        startTime = DateTime.Now;
        foreach (KeyValuePair<Sitecore.Data.ID, string> item in createdItems.Concat(createdChildItems))
        {
            ItemDefinition itemDef = new ItemDefinition(item.Key, item.Value, Sitecore.TemplateIDs.Folder, Sitecore.Data.ID.Null);
            dataProvider.GetParentID(itemDef, callContext);
        }
        Response.Write(string.Format("<tr><td>Get parent id's</td><td>{0}</td></tr>", DateTime.Now.Subtract(startTime).TotalMilliseconds));
        Response.Flush();

        Sitecore.Caching.CacheManager.ClearAllCaches();
        
        // Get the child id's for the items
        startTime = DateTime.Now;
        foreach (KeyValuePair<Sitecore.Data.ID, string> item in createdItems.Concat(createdChildItems))
        {
            ItemDefinition itemDef = new ItemDefinition(item.Key, item.Value, Sitecore.TemplateIDs.Folder, Sitecore.Data.ID.Null);
            dataProvider.GetChildIDs(itemDef, callContext);
        }
        Response.Write(string.Format("<tr><td>Get child id's</td><td>{0}</td></tr>", DateTime.Now.Subtract(startTime).TotalMilliseconds));
        Response.Flush();

        Sitecore.Caching.CacheManager.ClearAllCaches();
        
        // Get item definitions for the items
        startTime = DateTime.Now;
        foreach (KeyValuePair<Sitecore.Data.ID, string> item in createdItems.Concat(createdChildItems))
        {
            dataProvider.GetItemDefinition(item.Key, callContext);
        }
        Response.Write(string.Format("<tr><td>Get item definitions</td><td>{0}</td></tr>", DateTime.Now.Subtract(startTime).TotalMilliseconds));
        Response.Flush();

        Sitecore.Caching.CacheManager.ClearAllCaches();
        
        // Get the versions for the items
        startTime = DateTime.Now;
        foreach (KeyValuePair<Sitecore.Data.ID, string> item in createdItems.Concat(createdChildItems))
        {
            ItemDefinition itemDef = new ItemDefinition(item.Key, item.Value, Sitecore.TemplateIDs.Folder, Sitecore.Data.ID.Null);
            dataProvider.GetItemVersions(itemDef, callContext);
        }
        Response.Write(string.Format("<tr><td>Get item versions</td><td>{0}</td></tr>", DateTime.Now.Subtract(startTime).TotalMilliseconds));
        Response.Flush();

        Sitecore.Caching.CacheManager.ClearAllCaches();
        
        // Get field values for the items
        VersionUri vu = new VersionUri(Sitecore.Data.Managers.LanguageManager.GetLanguage("en"), new Sitecore.Data.Version(1));
        startTime = DateTime.Now;
        foreach (KeyValuePair<Sitecore.Data.ID, string> item in createdItems.Concat(createdChildItems))
        {
            ItemDefinition itemDef = new ItemDefinition(item.Key, item.Value, Sitecore.TemplateIDs.Folder, Sitecore.Data.ID.Null);
            dataProvider.GetItemFields(itemDef, vu, callContext);
        }
        Response.Write(string.Format("<tr><td>Get field values</td><td>{0}</td></tr>", DateTime.Now.Subtract(startTime).TotalMilliseconds));
        Response.Flush();

        Sitecore.Caching.CacheManager.ClearAllCaches();
        
        // Delete all the created items
        startTime = DateTime.Now;
        foreach (KeyValuePair<Sitecore.Data.ID, string> item in createdItems.Concat(createdChildItems).Reverse())
        {
            ItemDefinition itemDef = new ItemDefinition(item.Key, item.Value, Sitecore.TemplateIDs.Folder, Sitecore.Data.ID.Null);
            dataProvider.DeleteItem(itemDef, callContext);
        }
        Response.Write(string.Format("<tr><td>Delete</td><td>{0}</td></tr>", DateTime.Now.Subtract(startTime).TotalMilliseconds));
        Response.Flush();
            
        Response.Write("</table>");
    }

</script>
<form runat="server">

<asp:Repeater runat="server" ID="rptDataProviders">
<ItemTemplate>
<asp:CheckBox runat="server" ID="cbxIncludeProvider" Text='<%# string.Format("{0}: {1}", ((DataProvider) Container.DataItem).Database.Name, Container.DataItem.GetType().FullName) %>' /><br/>
Start item: <asp:TextBox runat="server" ID="tbxStartItemId" Text="{0DE95AE4-41AB-4D01-9EB0-67441B7C2450}" /><!-- {0FCC62A1-CDF9-4D04-BA9D-3ACCDC4A5F9D} -->
</ItemTemplate>
<SeparatorTemplate>
<br />
</SeparatorTemplate>
</asp:Repeater>

<p><asp:Button runat="server" Text="Run test" /></p>
</form>
</body>
</html>