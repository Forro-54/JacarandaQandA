<%@ Control Language="C#" AutoEventWireup="true" Inherits="DotNetNuke.Entities.Modules.ModuleSettingsBase" %>
<%@ Import Namespace="System" %>

<script runat="server">
    public override void LoadSettings()
    {
        base.LoadSettings();
        if (Page.IsPostBack) return;

        var canManage = CanManagePortalSettings();
        pnlPortalSettingsLink.Visible = canManage;
        pnlAdministratorNotice.Visible = !canManage;
        if (canManage) lnkPortalSettings.NavigateUrl = EditUrl("Administration");
    }

    public override void UpdateSettings()
    {
        // Jacaranda Q&A configuration is portal-wide from version 01.00.00.
    }

    private bool CanManagePortalSettings()
    {
        if (UserInfo == null) return false;
        if (UserInfo.IsSuperUser) return true;
        var role = PortalSettings == null ? String.Empty : (PortalSettings.AdministratorRoleName ?? String.Empty).Trim();
        return !String.IsNullOrWhiteSpace(role) && UserInfo.IsInRole(role);
    }
</script>

<div class="jacaranda-qa jqa-settings">
    <h2>Jacaranda Q&amp;A Settings</h2>
    <fieldset class="jqa-settings-section">
        <legend>Central administration</legend>
        <p class="jqa-setting-help">
            Jacaranda Q&amp;A uses one portal-wide administration screen for moderation and Q&amp;A-specific configuration. From version 01.00.03, Administrators can open it directly from the public Q&amp;A toolbar without entering DNN Edit Mode, or place the separate Jacaranda Q&amp;A Administration module on a secured DNN page. DNN's normal module title, container, visibility and permission settings remain managed by DNN itself.
        </p>
        <asp:Panel ID="pnlPortalSettingsLink" runat="server" Visible="false">
            <asp:HyperLink ID="lnkPortalSettings" runat="server" CssClass="jqa-secondary-button" Text="Open Q&amp;A Administration" />
        </asp:Panel>
        <asp:Panel ID="pnlAdministratorNotice" runat="server" Visible="false">
            <p class="jqa-setting-warning">Q&amp;A Administration is available only to a DNN portal Administrator or Superuser.</p>
        </asp:Panel>
    </fieldset>
</div>
