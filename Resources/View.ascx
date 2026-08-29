<%@ Control Language="C#" AutoEventWireup="true" Inherits="DotNetNuke.Entities.Modules.PortalModuleBase" %>
<%@ Register TagPrefix="dnn" TagName="texteditor" Src="~/controls/texteditor.ascx" %>
<%@ Import Namespace="System" %>
<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Net.Mail" %>
<%@ Import Namespace="System.Security.Cryptography" %>
<%@ Import Namespace="System.Text" %>
<%@ Import Namespace="System.Text.RegularExpressions" %>
<%@ Import Namespace="System.Web" %>
<%@ Import Namespace="System.Web.Security" %>
<%@ Import Namespace="DotNetNuke.Common.Utilities" %>
<%@ Import Namespace="DotNetNuke.Data" %>
<%@ Import Namespace="DotNetNuke.Entities.Users" %>
<%@ Import Namespace="DotNetNuke.Services.Exceptions" %>
<%@ Import Namespace="DotNetNuke.Services.Mail" %>
<%@ Import Namespace="DotNetNuke.Security" %>

<script runat="server">
    private const int MinimumQuestionLength = 5;
    private const int MinimumResponseLength = 2;
    private const int MaximumQuestionTitleLength = 250;
    private const int MaximumDisplayNameLength = 100;
    private const int MaximumGuestEmailLength = 254;
    private const int MaximumBlockedTermCount = 250;
    private const int MaximumBlockedTermLength = 100;
    private const int GuestEditWindowMinutes = 5;
    private const int MaximumRichAnswerHtmlLength = 50000;
    private const string SecurityTokenPrefix = "JacarandaQA_SecurityToken_";
    private const string CaptchaAnswerKey = "JacarandaQA_CaptchaAnswer";
    private const string ConversationCookiePrefix = "JacarandaQA_Conversation_";
    private const string GuestBrowserCookiePrefix = "JacarandaQA_GuestBrowser_";
    private const string GuestBrowserSessionKeyPrefix = "JacarandaQA_GuestBrowserSession_";
    private const string GuestEditTokenSessionKeyPrefix = "JacarandaQA_GuestEditToken_";
    private const string GuestEditQuestionSessionKeyPrefix = "JacarandaQA_GuestEditQuestion_";
    private const string PostMessagePrefix = "JacarandaQA_PostMessage_";
    private const string PostSuccessPrefix = "JacarandaQA_PostSuccess_";
    private const string PostRedirectStatusQueryKey = "jqaposted";
    private const string PostRedirectModuleQueryKey = "jqamid";
    private const string PostRedirectQuestionQueryKey = "jqaqid";
    private const string PostRedirectMessageAnchorPrefix = "jacaranda-qa-message-";
    private const string AdministrationTabQueryKey = "jqatab";
    private const string AdministrationStatusQueryKey = "jqaadminstatus";
    private const string AnswerQuestionQueryKey = "jqaqid";
    private const string AnswerModuleQueryKey = "jqamid";
    private const string AnswerActionQueryKey = "jqaaction";

    private PortalQaSettings _settings;
    private int? _focusedAnswerQuestionId;
    private bool _focusedAnswerMode;
    private int? _expandedQuestionId;

    private string QuestionsTable { get { return GetDnnTableName("JacarandaQAQuestions"); } }
    private string ResponsesTable { get { return GetDnnTableName("JacarandaQAResponses"); } }
    private string AnswerDraftsTable { get { return GetDnnTableName("JacarandaQAAnswerDrafts"); } }
    private string PortalSettingsTable { get { return GetDnnTableName("JacarandaQAPortalSettings"); } }
    private string ConnectionString { get { return Config.GetConnectionString(); } }
    private string SecurityTokenSessionKey { get { return SecurityTokenPrefix + PortalId + "_" + TabId + "_" + ModuleId + "_" + UserId; } }
    private string GuestEditTokenSessionKey { get { return GuestEditTokenSessionKeyPrefix + PortalId + "_" + TabId + "_" + ModuleId; } }
    private string GuestBrowserSessionKey { get { return GuestBrowserSessionKeyPrefix + PortalId; } }
    private string GuestEditQuestionSessionKey { get { return GuestEditQuestionSessionKeyPrefix + PortalId + "_" + TabId + "_" + ModuleId; } }
    protected string GuestCorrectionCountdownId { get { return "jqa-guest-correction-countdown-" + ModuleId; } }
    private string PostMessageSessionKey { get { return PostMessagePrefix + PortalId + "_" + TabId + "_" + ModuleId + "_" + UserId; } }
    private string PostSuccessSessionKey { get { return PostSuccessPrefix + PortalId + "_" + TabId + "_" + ModuleId + "_" + UserId; } }
    protected string PostRedirectMessageAnchorId { get { return PostRedirectMessageAnchorPrefix + ModuleId; } }
    protected string QaSiteTitle
    {
        get
        {
            var title = PortalSettings == null ? String.Empty : (PortalSettings.PortalName ?? String.Empty).Trim();
            return String.IsNullOrWhiteSpace(title) ? "This site" : title;
        }
    }

    protected string FollowUpGuidanceText
    {
        get
        {
            var maximum = _settings == null ? 4 : _settings.MaximumFollowUpQuestions;
            if (maximum <= 0) return "Follow-up questions are currently disabled on this site.";
            return "After your question has been answered, the original questioner may ask up to " + maximum + " related follow-up " + (maximum == 1 ? "question." : "questions.");
        }
    }

    protected void Page_Init(object sender, EventArgs e)
    {
        // The ministry answer TextEditor is declared statically in the ASCX,
        // matching DNN's standard HTML module. Static creation lets WebForms
        // restore editor state and postback data reliably before Save Draft/Publish.
        if (txtAnswerEditor != null)
        {
            txtAnswerEditor.ChooseMode = false;
            txtAnswerEditor.HtmlEncode = false;
            if (!Page.IsPostBack)
            {
                txtAnswerEditor.DefaultMode = "RICH";
                txtAnswerEditor.Mode = "RICH";
            }
        }
    }

    private void BindAnswerEditorModeSelector()
    {
        if (ddlAnswerEditorMode == null) return;

        ddlAnswerEditorMode.Items.Clear();
        
        if (txtAnswerEditor != null && txtAnswerEditor.IsRichEditorAvailable)
        {
            ddlAnswerEditorMode.Items.Add(new System.Web.UI.WebControls.ListItem("Rich Text Editor", "RICH"));
        }

        ddlAnswerEditorMode.Items.Add(new System.Web.UI.WebControls.ListItem("Basic Text Box", "BASIC"));

        var requestedMode = txtAnswerEditor == null ? "RICH" : (txtAnswerEditor.Mode ?? "RICH").ToUpperInvariant();
        var selected = ddlAnswerEditorMode.Items.FindByValue(requestedMode);
        if (selected == null)
        {
            requestedMode = ddlAnswerEditorMode.Items.FindByValue("RICH") != null ? "RICH" : "BASIC";
        }
        ddlAnswerEditorMode.SelectedValue = requestedMode;
    }

    protected void ddlAnswerEditorMode_SelectedIndexChanged(object sender, EventArgs e)
    {
        try
        {
            if (!CanManagePortalQandA()) return;

                        if (txtAnswerEditor == null) return;

            var requestedMode = String.Equals(ddlAnswerEditorMode.SelectedValue, "BASIC", StringComparison.OrdinalIgnoreCase)
                ? "BASIC"
                : "RICH";

            if (requestedMode == "RICH" && !txtAnswerEditor.IsRichEditorAvailable)
            {
                requestedMode = "BASIC";
            }

            // Mirror DNN's standard HTML module: the external selector changes
            // the TextEditor mode only when the administrator changes the list.
            txtAnswerEditor.ChangeMode(requestedMode);

            var matchingItem = ddlAnswerEditorMode.Items.FindByValue(requestedMode);
            if (matchingItem != null)
            {
                ddlAnswerEditorMode.ClearSelection();
                matchingItem.Selected = true;
            }

            int questionId;
            if (Int32.TryParse(hdnResponseQuestionId.Value, out questionId) && questionId > 0)
            {
                RegisterFollowUpContextFocusScript(questionId);
            }
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            ShowMessage("The answer editor mode could not be changed. Please try again.", false);
        }
    }

    protected void Page_Load(object sender, EventArgs e)
    {
        try
        {
            _settings = ReadPortalSettings();
            ConfigurePostingUi();
            ConfigureAdministrationToolbar();

            if (!Page.IsPostBack)
            {
                BindAnswerEditorModeSelector();
                EnsureSecurityToken();
                EnsureCaptchaChallenge();
                ApplyAdministrationAnswerContext();
                ApplyQuestionExpansionContext();
                BindQuestions();
                LoadGuestCorrectionPanel();
                ConsumePostRedirectMessage();
            }
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            ShowMessage("Jacaranda Q&A could not be loaded. Please try again later.", false);
        }
    }

    private void ApplyAdministrationAnswerContext()
    {
        if (Request == null || Request.QueryString == null || !CanManagePortalQandA()) return;
        if (!String.Equals(Request.QueryString[AnswerActionQueryKey], "answer", StringComparison.OrdinalIgnoreCase)) return;

        int requestedModuleId;
        int questionId;
        if (!Int32.TryParse(Request.QueryString[AnswerModuleQueryKey], out requestedModuleId) || requestedModuleId != ModuleId) return;
        if (!Int32.TryParse(Request.QueryString[AnswerQuestionQueryKey], out questionId) || questionId <= 0) return;

        var question = GetQuestion(questionId, true);
        if (question == null || question.QuestionStatus != 0) return;

        EnterFocusedAnswerMode(question);
        SetResponseContext(question, true);
        RegisterAnswerContextFocusScript(question.QuestionId);
    }


    private void ApplyQuestionExpansionContext()
    {
        if (_focusedAnswerMode && _focusedAnswerQuestionId.HasValue)
        {
            _expandedQuestionId = _focusedAnswerQuestionId.Value;
            return;
        }

        if (Request == null || Request.QueryString == null) return;

        int requestedModuleId;
        var rawModuleId = Request.QueryString[AnswerModuleQueryKey];
        if (!String.IsNullOrWhiteSpace(rawModuleId)
            && (!Int32.TryParse(rawModuleId, out requestedModuleId) || requestedModuleId != ModuleId))
        {
            return;
        }

        int questionId;
        if (Int32.TryParse(Request.QueryString[AnswerQuestionQueryKey], out questionId) && questionId > 0)
        {
            _expandedQuestionId = questionId;
        }
    }

    private void RegisterAnswerContextFocusScript(int questionId)
    {
        RegisterResponseContextFocusScript(questionId, false);
    }

    private void RegisterFollowUpContextFocusScript(int questionId)
    {
        RegisterResponseContextFocusScript(questionId, true);
    }

    private void RegisterResponseContextFocusScript(int questionId, bool focusResponseForm)
    {
        if (Page == null) return;
        var responseId = HttpUtility.JavaScriptStringEncode(pnlResponseForm.ClientID);
        var questionAnchor = HttpUtility.JavaScriptStringEncode("jqa-question-" + questionId);
        var focusResponse = focusResponseForm ? "true" : "false";
        var script = @"
(function () {
    var response = document.getElementById('" + responseId + @"');
    var question = document.getElementById('" + questionAnchor + @"');
    if (question) {
        try {
            var all = document.querySelectorAll('.jqa-question.jqa-question-expanded');
            for (var i = 0; i < all.length; i++) {
                if (all[i] !== question) {
                    all[i].classList.remove('jqa-question-expanded');
                    var otherToggle = all[i].querySelector('[data-jqa-question-toggle]');
                    if (otherToggle) otherToggle.setAttribute('aria-expanded', 'false');
                }
            }
            question.classList.add('jqa-question-expanded');
            var toggle = question.querySelector('[data-jqa-question-toggle]');
            if (toggle) toggle.setAttribute('aria-expanded', 'true');
        } catch (expandError) { }
    }
    if (question && response) {
        try {
            // Keep the response editor visually attached to the conversation it belongs to.
            // Place it inside the collapsible question body after the existing answers,
            // follow-ups and actions instead of at the bottom of the complete Q&A page.
            var questionBody = question.querySelector('.jqa-question-body');
            (questionBody || question).appendChild(response);
        } catch (moveError) { }
    }
    var target = (" + focusResponse + @" && response) ? response : (question || response);
    if (!target) { return; }
    window.setTimeout(function () {
        try {
            target.setAttribute('tabindex', '-1');
            target.scrollIntoView({ behavior: 'auto', block: 'start' });
            target.focus();
        } catch (e) {
            try { target.scrollIntoView(true); } catch (ignore) { }
        }
    }, 50);
})();";
        RegisterStartupScript("JacarandaQandAResponseFocus_" + ModuleId + "_" + questionId + "_" + (focusResponseForm ? "response" : "question"), script);
    }

    private void EnterFocusedAnswerMode(QuestionRow question)
    {
        if (question == null) return;
        _focusedAnswerMode = true;
        _focusedAnswerQuestionId = question.QuestionId;
        _expandedQuestionId = question.QuestionId;
        pnlAskSection.Visible = false;
        litQuestionsHeading.Text = "Question to Answer";
    }

    private void ConfigurePostingUi()
    {
        var registered = UserInfo != null && UserInfo.UserID > 0;
        var guestAllowed = _settings.PostingEnabled && _settings.GuestPostingEnabled;
        var canAsk = _settings.PostingEnabled && (registered || guestAllowed);

        pnlAskLauncher.Visible = canAsk;
        pnlAskQuestion.Visible = canAsk;
        pnlGuestIdentity.Visible = !registered && guestAllowed;
        pnlPostingClosed.Visible = !_settings.PostingEnabled;
        pnlLoginRequired.Visible = _settings.PostingEnabled && !registered && !_settings.GuestPostingEnabled;

        // The public question form is intentionally collapsed on a normal page load.
        // If posting is unavailable, leave the information panel visible so the visitor
        // can see why a new question cannot currently be submitted.
        if (!Page.IsPostBack)
        {
            pnlAskForm.Visible = !canAsk;
        }
        UpdateAskQuestionToggle();

        if (registered)
        {
            litQuestionIdentity.Text = HttpUtility.HtmlEncode(GetCurrentUserDisplayName());
            pnlRegisteredIdentity.Visible = true;
        }
        else
        {
            pnlRegisteredIdentity.Visible = false;
        }

        txtQuestion.MaxLength = _settings.MaximumQuestionLength;
        txtResponse.MaxLength = _settings.MaximumResponseLength;
        pnlQuestionCaptcha.Visible = CaptchaAppliesToCurrentUser();
        pnlResponseCaptcha.Visible = CaptchaAppliesToCurrentUser();
    }

    protected void btnToggleAskQuestion_Click(object sender, EventArgs e)
    {
        if (_focusedAnswerMode) return;

        _settings = ReadPortalSettings();
        var registered = UserInfo != null && UserInfo.UserID > 0;
        var guestAllowed = _settings.PostingEnabled && _settings.GuestPostingEnabled;
        var canAsk = _settings.PostingEnabled && (registered || guestAllowed);
        if (!canAsk) return;

        pnlAskForm.Visible = !pnlAskForm.Visible;
        UpdateAskQuestionToggle();

        if (pnlAskForm.Visible)
        {
            RegisterAskQuestionFocusScript();
        }
    }

    private void UpdateAskQuestionToggle()
    {
        if (btnToggleAskQuestion == null) return;
        var expanded = pnlAskForm != null && pnlAskForm.Visible;
        btnToggleAskQuestion.Text = expanded ? "Close Question Form" : "Ask a Question";
        btnToggleAskQuestion.Attributes["aria-expanded"] = expanded ? "true" : "false";
        btnToggleAskQuestion.Attributes["aria-controls"] = pnlAskForm == null ? String.Empty : pnlAskForm.ClientID;
    }

    private void RegisterAskQuestionFocusScript()
    {
        if (Page == null || pnlAskForm == null) return;
        var targetId = HttpUtility.JavaScriptStringEncode(pnlAskForm.ClientID);
        var script = @"
(function () {
    var target = document.getElementById('" + targetId + @"');
    if (!target) { return; }
    window.setTimeout(function () {
        try {
            target.setAttribute('tabindex', '-1');
            target.scrollIntoView({ behavior: 'auto', block: 'start' });
            target.focus();
        } catch (e) {
            try { target.scrollIntoView(true); } catch (ignore) { }
        }
    }, 30);
})();";
        RegisterStartupScript("JacarandaQandAAskFocus_" + ModuleId, script);
    }

    private void ConfigureAdministrationToolbar()
    {
        var canManage = CanManagePortalQandA();
        pnlAdminToolbar.Visible = canManage;
        if (!canManage) return;

        var pendingCount = 0;
        var awaitingCount = 0;

        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT
    (SELECT COUNT(1) FROM " + QuestionsTable + @" WHERE PortalId = @PortalId AND IsDeleted = 0 AND IsApproved = 0)
  + (SELECT COUNT(1) FROM " + ResponsesTable + @" WHERE PortalId = @PortalId AND IsDeleted = 0 AND IsApproved = 0) AS PendingCount,
    (SELECT COUNT(1) FROM " + QuestionsTable + @" WHERE PortalId = @PortalId AND IsDeleted = 0 AND IsApproved = 1 AND QuestionStatus = 0) AS AwaitingCount;";
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                if (reader.Read())
                {
                    pendingCount = reader["PendingCount"] == DBNull.Value ? 0 : Convert.ToInt32(reader["PendingCount"]);
                    awaitingCount = reader["AwaitingCount"] == DBNull.Value ? 0 : Convert.ToInt32(reader["AwaitingCount"]);
                }
            }
        }

        litAdminPendingCount.Text = pendingCount.ToString();
        litAdminAwaitingCount.Text = awaitingCount.ToString();

        var standaloneAdministrationUrl = ResolveStandaloneAdministrationUrl();
        if (!String.IsNullOrWhiteSpace(standaloneAdministrationUrl))
        {
            lnkAdministration.NavigateUrl = standaloneAdministrationUrl;
            lnkAdministration.ToolTip = "Open the standalone Jacaranda Q&A Administration page";
            return;
        }

        try
        {
            lnkAdministration.NavigateUrl = EditUrl("Administration");
            lnkAdministration.ToolTip = "Standalone Q&A Administration has not yet been placed on a DNN page; opening the internal administration control instead.";
        }
        catch
        {
            lnkAdministration.NavigateUrl = DotNetNuke.Common.Globals.NavigateURL(TabId);
        }
    }

    private string ResolveStandaloneAdministrationUrl()
    {
        try
        {
            var tabsTable = GetDnnTableName("Tabs");
            var tabModulesTable = GetDnnTableName("TabModules");
            var modulesTable = GetDnnTableName("Modules");
            var moduleDefinitionsTable = GetDnnTableName("ModuleDefinitions");
            var desktopModulesTable = GetDnnTableName("DesktopModules");

            using (var connection = new SqlConnection(ConnectionString))
            using (var command = connection.CreateCommand())
            {
                command.CommandText = @"
SELECT TOP 1 t.TabID
FROM " + tabsTable + @" t
INNER JOIN " + tabModulesTable + @" tm ON tm.TabID = t.TabID
INNER JOIN " + modulesTable + @" m ON m.ModuleID = tm.ModuleID
INNER JOIN " + moduleDefinitionsTable + @" md ON md.ModuleDefID = m.ModuleDefID
INNER JOIN " + desktopModulesTable + @" dm ON dm.DesktopModuleID = md.DesktopModuleID
WHERE t.PortalID = @PortalId
  AND ISNULL(t.IsDeleted, 0) = 0
  AND dm.ModuleName = @AdministrationModuleName
ORDER BY CASE WHEN t.TabID = @CurrentTabId THEN 1 ELSE 0 END, t.TabID;";
                command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                command.Parameters.Add("@CurrentTabId", SqlDbType.Int).Value = TabId;
                command.Parameters.Add("@AdministrationModuleName", SqlDbType.NVarChar, 128).Value = "Jacaranda_QandA_Administration";
                connection.Open();
                var result = command.ExecuteScalar();
                if (result != null && result != DBNull.Value)
                {
                    var administrationTabId = Convert.ToInt32(result);
                    if (administrationTabId > 0)
                        return DotNetNuke.Common.Globals.NavigateURL(administrationTabId);
                }
            }
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
        }
        return String.Empty;
    }

    private void RedirectToAdministrationAfterDraftSave()
    {
        var administrationUrl = ResolveStandaloneAdministrationUrl();
        if (String.IsNullOrWhiteSpace(administrationUrl))
        {
            try
            {
                administrationUrl = EditUrl("Administration");
            }
            catch
            {
                administrationUrl = DotNetNuke.Common.Globals.NavigateURL(TabId);
            }
        }

        var separator = administrationUrl.IndexOf('?') >= 0 ? "&" : "?";
        administrationUrl += separator
            + AdministrationTabQueryKey + "=awaiting"
            + "&" + AdministrationStatusQueryKey + "=draftsaved";

        Response.Redirect(administrationUrl, false);
        Context.ApplicationInstance.CompleteRequest();
    }

    protected void btnSubmitQuestion_Click(object sender, EventArgs e)
    {
        try
        {
            _settings = ReadPortalSettings();
            if (!_settings.PostingEnabled)
            {
                ShowMessage("New questions are temporarily closed.", false);
                return;
            }

            var registered = UserInfo != null && UserInfo.UserID > 0;
            var isGuest = !registered;
            if (isGuest && !_settings.GuestPostingEnabled)
            {
                ShowMessage("Please sign in before asking a question.", false);
                return;
            }

            if (!ValidateSecurityToken())
            {
                ShowMessage("The form security token expired. Please refresh the page and try again.", false);
                return;
            }

            if (!String.IsNullOrWhiteSpace(txtWebsite.Text))
            {
                ShowMessage("The question could not be submitted.", false);
                return;
            }

            var title = NormalizeSingleLineText(txtQuestionTitle.Text);
            var text = (txtQuestion.Text ?? String.Empty).Trim();
            if (title.Length < 3 || title.Length > MaximumQuestionTitleLength)
            {
                ShowMessage("Please enter a question title between 3 and 250 characters.", false);
                return;
            }
            if (text.Length < MinimumQuestionLength || text.Length > _settings.MaximumQuestionLength)
            {
                ShowMessage("Please enter a question between " + MinimumQuestionLength + " and " + _settings.MaximumQuestionLength + " characters.", false);
                return;
            }

            var displayName = registered ? GetCurrentUserDisplayName() : NormalizeSingleLineText(txtGuestName.Text);
            var guestEmail = isGuest ? (txtGuestEmail.Text ?? String.Empty).Trim() : String.Empty;
            var encryptedGuestEmail = String.Empty;
            var guestRateKey = isGuest ? ComputeGuestRateLimitKey() : String.Empty;
            var conversationToken = String.Empty;
            var conversationHash = String.Empty;
            var guestEditToken = String.Empty;
            var guestEditTokenHash = String.Empty;

            if (displayName.Length < 2 || displayName.Length > MaximumDisplayNameLength)
            {
                ShowMessage("Please enter a valid display name.", false);
                return;
            }

            if (isGuest)
            {
                if (!IsValidEmailAddress(guestEmail))
                {
                    ShowMessage("Please enter a valid private email address.", false);
                    return;
                }
                if (!TryProtectGuestEmail(guestEmail, out encryptedGuestEmail))
                {
                    ShowMessage("Your private email address could not be protected. The question was not submitted.", false);
                    return;
                }
                conversationToken = GenerateSecurityToken();
                conversationHash = ComputeConversationTokenHash(conversationToken);
                guestEditToken = GenerateSecurityToken();
                guestEditTokenHash = ComputeGuestEditTokenHash(guestEditToken);
                if (String.IsNullOrWhiteSpace(guestRateKey) || String.IsNullOrWhiteSpace(conversationHash) || String.IsNullOrWhiteSpace(guestEditTokenHash))
                {
                    ShowMessage("The secure guest session could not be created. Please try again.", false);
                    return;
                }
            }

            if (HasActiveQuestionForCurrentQuestioner(isGuest, guestRateKey))
            {
                ShowMessage("You already have a question or follow-up awaiting moderation or an answer. Jacaranda Q&A accepts one active question at a time. Please continue that conversation or wait until it has been answered.", false);
                return;
            }

            string captchaError;
            if (!ValidateCaptcha(txtQuestionCaptcha, out captchaError))
            {
                ShowMessage(captchaError, false);
                GenerateCaptchaChallenge();
                return;
            }

            string rateError;
            if (!CheckRateLimit(isGuest, guestRateKey, out rateError))
            {
                ShowMessage(rateError, false);
                return;
            }

            var languageFlagged = ContainsBlockedLanguage(title + " " + text);
            var approved = CanManagePortalQandA() || (!isGuest && !_settings.RequireRegisteredModeration);
            var questionId = InsertQuestion(title, text, displayName, isGuest, encryptedGuestEmail, guestRateKey, guestEditTokenHash, conversationHash, approved, languageFlagged);
            if (questionId <= 0)
            {
                ShowMessage("You already have a question or follow-up awaiting moderation or an answer. Jacaranda Q&A accepts one active question at a time.", false);
                return;
            }

            if (isGuest && questionId > 0)
            {
                SetConversationCookie(questionId, conversationToken);
                SetGuestEditSession(questionId, guestEditToken);
            }

            SendAdministratorSubmissionNotification(questionId, title, displayName, text, isGuest, guestEmail, approved, false, languageFlagged);
            if (!approved)
            {
                var savedQuestion = GetQuestion(questionId, false);
                if (savedQuestion != null)
                {
                    SendQuestionerModerationAcknowledgement(savedQuestion);
                }
            }

            var completionMessage = approved
                ? "Your question has been added and is awaiting an answer."
                : (isGuest
                    ? "Thank you. Your question has been received and is awaiting moderation. You have 5 minutes to review and correct its title or text below."
                    : "Thank you. Your question has been received and is awaiting moderation.");
            CompletePublicPost(completionMessage, true, questionId);
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            ShowMessage("The question could not be submitted. Please try again later.", false);
        }
    }

    protected void rptQuestions_ItemCommand(object source, System.Web.UI.WebControls.RepeaterCommandEventArgs e)
    {
        int questionId;
        if (!Int32.TryParse(Convert.ToString(e.CommandArgument), out questionId) || questionId <= 0) return;

        var question = GetQuestion(questionId, true);
        if (question == null) return;

        if (String.Equals(e.CommandName, "Answer", StringComparison.OrdinalIgnoreCase))
        {
            if (!CanManagePortalQandA() || question.QuestionStatus != 0) return;
            EnterFocusedAnswerMode(question);
            SetResponseContext(question, true);
            BindQuestions();
            RegisterAnswerContextFocusScript(question.QuestionId);
        }
        else if (String.Equals(e.CommandName, "FollowUp", StringComparison.OrdinalIgnoreCase))
        {
            if (!CanQuestionerFollowUp(question) || question.QuestionStatus == 2) return;
            _expandedQuestionId = question.QuestionId;
            SetResponseContext(question, false);
            RegisterFollowUpContextFocusScript(question.QuestionId);
        }
    }

    protected void btnCancelResponse_Click(object sender, EventArgs e)
    {
        ClearResponseContext();
        _focusedAnswerMode = false;
        _focusedAnswerQuestionId = null;
        _expandedQuestionId = null;
        pnlAskSection.Visible = true;
        pnlAskForm.Visible = false;
        UpdateAskQuestionToggle();
        litQuestionsHeading.Text = "Questions &amp; Answers";
        BindQuestions();
    }

    private string GetSubmittedMinistryAnswerHtml()
    {
        // DNN's standard HTML module reads the statically-declared TextEditor.Text
        // directly on save. Use the same lifecycle-safe pattern here.
        return txtAnswerEditor == null ? String.Empty : (txtAnswerEditor.Text ?? String.Empty);
    }

    protected void btnSaveDraft_Click(object sender, EventArgs e)
    {
        try
        {
            _settings = ReadPortalSettings();
            if (!CanManagePortalQandA())
            {
                ShowMessage("You do not have permission to save answer drafts.", false);
                return;
            }
            if (!ValidateSecurityToken())
            {
                ShowMessage("The form security token expired. Please refresh the page and try again.", false);
                return;
            }

            int questionId;
            if (!Int32.TryParse(hdnResponseQuestionId.Value, out questionId) || questionId <= 0
                || !String.Equals(hdnResponseMode.Value, "answer", StringComparison.Ordinal))
            {
                ShowMessage("The selected question could not be found.", false);
                return;
            }

            var question = GetQuestion(questionId, true);
            if (question == null || question.QuestionStatus != 0)
            {
                ShowMessage("This question is no longer awaiting an answer, so the draft cannot be saved.", false);
                ClearResponseContext();
                return;
            }

            var rawHtml = GetSubmittedMinistryAnswerHtml();
            if (rawHtml.Length > MaximumRichAnswerHtmlLength)
            {
                ShowResponseMessageAndRefocus("The formatted answer is too large. Please shorten it and try again.", questionId);
                return;
            }

            var cleanHtml = SanitizeMinistryAnswerHtml(rawHtml);
            var plainText = RichTextToPlainText(cleanHtml).Trim();
            if (plainText.Length < MinimumResponseLength || plainText.Length > _settings.MaximumResponseLength)
            {
                ShowResponseMessageAndRefocus("Please enter draft text between " + MinimumResponseLength + " and " + _settings.MaximumResponseLength + " characters.", questionId);
                return;
            }

            if (!SaveAnswerDraft(question, cleanHtml))
            {
                ShowResponseMessageAndRefocus("The draft could not be saved because this question is no longer awaiting an answer.", questionId);
                return;
            }

            RedirectToAdministrationAfterDraftSave();
            return;
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            ShowMessage("The answer draft could not be saved. Please try again later.", false);
        }
    }

    protected void btnSubmitResponse_Click(object sender, EventArgs e)
    {
        try
        {
            _settings = ReadPortalSettings();
            if (!_settings.PostingEnabled)
            {
                ShowMessage("New responses are temporarily closed.", false);
                return;
            }
            if (!ValidateSecurityToken())
            {
                ShowMessage("The form security token expired. Please refresh the page and try again.", false);
                return;
            }
            if (!String.IsNullOrWhiteSpace(txtResponseWebsite.Text))
            {
                ShowMessage("The response could not be submitted.", false);
                return;
            }

            int questionId;
            if (!Int32.TryParse(hdnResponseQuestionId.Value, out questionId) || questionId <= 0)
            {
                ShowMessage("The selected question could not be found.", false);
                return;
            }

            var question = GetQuestion(questionId, true);
            if (question == null || question.QuestionStatus == 2)
            {
                ShowMessage("This question is no longer open for responses.", false);
                ClearResponseContext();
                return;
            }

            var requestedAnswer = String.Equals(hdnResponseMode.Value, "answer", StringComparison.Ordinal);
            var ministryAnswer = requestedAnswer && CanManagePortalQandA() && question.QuestionStatus == 0;

            if (!requestedAnswer && IsOriginalQuestioner(question) && HasReachedFollowUpLimit(question.QuestionId))
            {
                ShowResponseMessageAndRefocus(GetFollowUpLimitMessage(), question.QuestionId);
                return;
            }

            var questionerFollowUp = !requestedAnswer && CanQuestionerFollowUp(question);
            if (!ministryAnswer && !questionerFollowUp)
            {
                ShowResponseMessageAndRefocus("You do not have permission to add this response.", question.QuestionId);
                return;
            }

            string text;
            string plainTextForValidation;
            if (ministryAnswer)
            {
                var rawHtml = GetSubmittedMinistryAnswerHtml();
                if (rawHtml.Length > MaximumRichAnswerHtmlLength)
                {
                    ShowResponseMessageAndRefocus("The formatted answer is too large. Please shorten it and try again.", question.QuestionId);
                    return;
                }
                text = SanitizeMinistryAnswerHtml(rawHtml);
                plainTextForValidation = RichTextToPlainText(text).Trim();
            }
            else
            {
                text = (txtResponse.Text ?? String.Empty).Trim();
                plainTextForValidation = text;
            }

            if (plainTextForValidation.Length < MinimumResponseLength || plainTextForValidation.Length > _settings.MaximumResponseLength)
            {
                ShowResponseMessageAndRefocus("Please enter a response between " + MinimumResponseLength + " and " + _settings.MaximumResponseLength + " characters.", question.QuestionId);
                return;
            }

            string captchaError;
            if (!ministryAnswer && !ValidateCaptcha(txtResponseCaptcha, out captchaError))
            {
                ShowResponseMessageAndRefocus(captchaError, question.QuestionId);
                GenerateCaptchaChallenge();
                return;
            }

            var isGuest = questionerFollowUp && (question.UserId == null || question.UserId.Value <= 0);
            var guestRateKey = isGuest ? ComputeGuestRateLimitKey() : String.Empty;
            string rateError;
            if (!ministryAnswer && !CheckRateLimit(isGuest, guestRateKey, out rateError))
            {
                ShowResponseMessageAndRefocus(rateError, question.QuestionId);
                return;
            }

            var displayName = ministryAnswer ? GetCurrentUserDisplayName() : question.DisplayName;
            var responseType = ministryAnswer ? 1 : 2;
            var approved = ministryAnswer || (!isGuest && !_settings.RequireRegisteredModeration);
            var languageFlagged = ContainsBlockedLanguage(plainTextForValidation);
            var responseId = InsertResponse(question, responseType, displayName, text, isGuest, guestRateKey, approved, languageFlagged);
            if (responseId <= 0)
            {
                var blockedMessage = ministryAnswer
                    ? "This question is no longer awaiting an answer."
                    : (HasReachedFollowUpLimit(question.QuestionId)
                        ? GetFollowUpLimitMessage()
                        : "A follow-up is already awaiting moderation or this question is no longer ready for another follow-up.");
                ShowResponseMessageAndRefocus(blockedMessage, question.QuestionId);
                return;
            }

            if (ministryAnswer)
            {
                SendQuestionerAnswerNotification(question, RichTextToPlainText(text));
            }
            else
            {
                SendAdministratorSubmissionNotification(question.QuestionId, question.QuestionTitle, displayName, text, isGuest, String.Empty, approved, true, languageFlagged);
            }

            var completionMessage = approved
                ? (ministryAnswer ? "The answer has been published." : "Your follow-up has been added and the question is awaiting another answer.")
                : "Thank you. Your follow-up has been received and is awaiting moderation.";
            CompletePublicPost(completionMessage, true, question.QuestionId);
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            ShowMessage("The response could not be submitted. Please try again later.", false);
        }
    }


    private void CompletePublicPost(string message, bool success, int questionId)
    {
        QueuePostCompletionMessage(message, success);

        if (TryRedirectAfterSuccessfulPost(questionId))
        {
            return;
        }

        // Defensive fallback: if DNN/IIS does not honour the redirect for any
        // reason, complete the UI update in the current request instead of
        // leaving the visitor with an apparently unchanged form.
        ClearQuestionForm();
        ClearResponseContext();
        pnlAskForm.Visible = false;
        UpdateAskQuestionToggle();
        EnsureSecurityToken(true);
        GenerateCaptchaChallenge();
        BindQuestions();
        LoadGuestCorrectionPanel();
        ShowMessage(message, success);
        RegisterCompletionFocusScript();
        ClearQueuedPostCompletionMessage();
    }

    private void QueuePostCompletionMessage(string message, bool success)
    {
        if (Session == null) return;
        Session[PostMessageSessionKey] = message ?? String.Empty;
        Session[PostSuccessSessionKey] = success.ToString();
    }

    private void ClearQueuedPostCompletionMessage()
    {
        if (Session == null) return;
        Session.Remove(PostMessageSessionKey);
        Session.Remove(PostSuccessSessionKey);
    }

    private bool TryRedirectAfterSuccessfulPost(int questionId)
    {
        if (Response == null) return false;

        var redirectUrl = BuildPostRedirectUrl(questionId);
        if (String.IsNullOrWhiteSpace(redirectUrl)) return false;

        try
        {
            Response.Redirect(redirectUrl, false);
            if (Context != null && Context.ApplicationInstance != null)
            {
                Context.ApplicationInstance.CompleteRequest();
            }
            return true;
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            return false;
        }
    }

    private string BuildPostRedirectUrl(int questionId)
    {
        try
        {
            var args = new List<string> {
                PostRedirectStatusQueryKey + "=1",
                PostRedirectModuleQueryKey + "=" + ModuleId.ToString()
            };

            if (questionId > 0)
            {
                args.Add(PostRedirectQuestionQueryKey + "=" + questionId.ToString());
            }

            var url = DotNetNuke.Common.Globals.NavigateURL(TabId, String.Empty, args.ToArray());
            if (String.IsNullOrWhiteSpace(url)) return String.Empty;

            var hashIndex = url.IndexOf('#');
            if (hashIndex >= 0) url = url.Substring(0, hashIndex);

            return url + "#" + PostRedirectMessageAnchorId;
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            return String.Empty;
        }
    }

    private void ConsumePostRedirectMessage()
    {
        if (Session == null) return;

        // Prefer an explicit completion marker for this module. The queued
        // session message remains a one-time value, so copied/refreshed URLs
        // cannot recreate an old success notification.
        var validRedirect = false;
        if (Request != null && Request.QueryString != null)
        {
            int redirectModuleId;
            validRedirect = String.Equals(Request.QueryString[PostRedirectStatusQueryKey], "1", StringComparison.Ordinal)
                && Int32.TryParse(Request.QueryString[PostRedirectModuleQueryKey], out redirectModuleId)
                && redirectModuleId == ModuleId;
        }

        var message = Convert.ToString(Session[PostMessageSessionKey]);
        if (String.IsNullOrWhiteSpace(message)) return;

        var success = true;
        try
        {
            if (Session[PostSuccessSessionKey] != null)
            {
                success = Convert.ToBoolean(Session[PostSuccessSessionKey]);
            }
        }
        catch { success = true; }

        ClearQueuedPostCompletionMessage();
        ShowMessage(message, success);
        RegisterCompletionFocusScript();

        if (validRedirect)
        {
            RegisterCleanPostRedirectUrlScript();
        }
    }

    private void RegisterCompletionFocusScript()
    {
        if (Page == null) return;
        var anchorId = HttpUtility.JavaScriptStringEncode(PostRedirectMessageAnchorId);
        var script = @"
(function () {
    var target = document.getElementById('" + anchorId + @"');
    if (!target) { return; }
    try { target.setAttribute('tabindex', '-1'); target.focus(); } catch (e) { }
})();";
        RegisterStartupScript("JacarandaQandACompletionFocus_" + ModuleId, script);
    }

    private void RegisterCleanPostRedirectUrlScript()
    {
        if (Page == null) return;

        string cleanUrl;
        try
        {
            cleanUrl = DotNetNuke.Common.Globals.NavigateURL(TabId, String.Empty) + "#" + PostRedirectMessageAnchorId;
        }
        catch
        {
            cleanUrl = "#" + PostRedirectMessageAnchorId;
        }

        var script = @"
(function () {
    if (!window.history || !window.history.replaceState) { return; }
    try {
        window.history.replaceState(null, document.title, '" + HttpUtility.JavaScriptStringEncode(cleanUrl) + @"');
    } catch (e) { }
})();";
        RegisterStartupScript("JacarandaQandACleanPostRedirectUrl_" + ModuleId, script);
    }

    private void RegisterStartupScript(string key, string script)
    {
        if (Page == null || String.IsNullOrWhiteSpace(key) || String.IsNullOrWhiteSpace(script)) return;
        if (Page.ClientScript != null)
        {
            Page.ClientScript.RegisterStartupScript(GetType(), key, script, true);
        }
    }

    private int InsertQuestion(string title, string text, string displayName, bool isGuest, string encryptedEmail, string guestRateKey, string guestEditTokenHash, string conversationHash, bool approved, bool languageFlagged)
    {
        using (var connection = new SqlConnection(ConnectionString))
        {
            connection.Open();
            using (var transaction = connection.BeginTransaction(IsolationLevel.Serializable))
            {
                try
                {
                    using (var guard = connection.CreateCommand())
                    {
                        guard.Transaction = transaction;
                        guard.CommandText = @"
SELECT COUNT(1)
FROM " + QuestionsTable + @" q WITH (UPDLOCK, HOLDLOCK)
WHERE q.PortalId = @PortalId
  AND q.IsDeleted = 0
  AND q.QuestionStatus <> 2
  AND ((@IsGuest = 0 AND q.UserId = @UserId)
       OR (@IsGuest = 1 AND q.UserId IS NULL AND q.GuestRateLimitKey = @GuestRateLimitKey))
  AND (q.IsApproved = 0
       OR q.QuestionStatus = 0
       OR EXISTS (
            SELECT 1 FROM " + ResponsesTable + @" r WITH (UPDLOCK, HOLDLOCK)
            WHERE r.QuestionId = q.QuestionId
              AND r.PortalId = q.PortalId
              AND r.IsDeleted = 0
              AND r.IsApproved = 0
              AND r.ResponseType = 2));";
                        guard.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                        guard.Parameters.Add("@IsGuest", SqlDbType.Bit).Value = isGuest;
                        guard.Parameters.Add("@UserId", SqlDbType.Int).Value = isGuest ? (object)DBNull.Value : UserId;
                        guard.Parameters.Add("@GuestRateLimitKey", SqlDbType.NVarChar, 64).Value = isGuest ? (object)(guestRateKey ?? String.Empty) : DBNull.Value;
                        if (Convert.ToInt32(guard.ExecuteScalar()) > 0)
                        {
                            transaction.Rollback();
                            return 0;
                        }
                    }

                    using (var command = connection.CreateCommand())
                    {
                        command.Transaction = transaction;
                        command.CommandText = @"
INSERT INTO " + QuestionsTable + @"
(PortalId, TabId, ModuleId, UserId, DisplayName, GuestEmailEncrypted, GuestRateLimitKey, GuestEditTokenHash, GuestConversationTokenHash,
 QuestionTitle, QuestionText, QuestionStatus, IsApproved, IsDeleted, IsLanguageFlagged, CreatedOnDate, CreatedByUserId)
VALUES
(@PortalId, @TabId, @ModuleId, @UserId, @DisplayName, @GuestEmailEncrypted, @GuestRateLimitKey, @GuestEditTokenHash, @GuestConversationTokenHash,
 @QuestionTitle, @QuestionText, 0, @IsApproved, 0, @IsLanguageFlagged, GETUTCDATE(), @CreatedByUserId);
SELECT CAST(SCOPE_IDENTITY() AS INT);";
                        command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                        command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
                        command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
                        command.Parameters.Add("@UserId", SqlDbType.Int).Value = isGuest ? (object)DBNull.Value : UserId;
                        command.Parameters.Add("@DisplayName", SqlDbType.NVarChar, 100).Value = Truncate(displayName, 100);
                        command.Parameters.Add("@GuestEmailEncrypted", SqlDbType.NVarChar, 2048).Value = isGuest ? (object)encryptedEmail : DBNull.Value;
                        command.Parameters.Add("@GuestRateLimitKey", SqlDbType.NVarChar, 64).Value = isGuest ? (object)guestRateKey : DBNull.Value;
                        command.Parameters.Add("@GuestEditTokenHash", SqlDbType.NVarChar, 64).Value = isGuest ? (object)guestEditTokenHash : DBNull.Value;
                        command.Parameters.Add("@GuestConversationTokenHash", SqlDbType.NVarChar, 64).Value = isGuest ? (object)conversationHash : DBNull.Value;
                        command.Parameters.Add("@QuestionTitle", SqlDbType.NVarChar, 250).Value = title;
                        command.Parameters.Add("@QuestionText", SqlDbType.NVarChar, _settings.MaximumQuestionLength).Value = text;
                        command.Parameters.Add("@IsApproved", SqlDbType.Bit).Value = approved;
                        command.Parameters.Add("@IsLanguageFlagged", SqlDbType.Bit).Value = languageFlagged;
                        command.Parameters.Add("@CreatedByUserId", SqlDbType.Int).Value = isGuest ? (object)DBNull.Value : UserId;
                        var questionId = Convert.ToInt32(command.ExecuteScalar());
                        transaction.Commit();
                        return questionId;
                    }
                }
                catch
                {
                    try { transaction.Rollback(); } catch { }
                    throw;
                }
            }
        }
    }

    private int InsertResponse(QuestionRow question, int responseType, string displayName, string text, bool isGuest, string guestRateKey, bool approved, bool languageFlagged)
    {
        using (var connection = new SqlConnection(ConnectionString))
        {
            connection.Open();
            using (var transaction = connection.BeginTransaction(IsolationLevel.Serializable))
            {
                try
                {
                    int currentStatus;
                    using (var guard = connection.CreateCommand())
                    {
                        guard.Transaction = transaction;
                        guard.CommandText = @"
SELECT QuestionStatus
FROM " + QuestionsTable + @" WITH (UPDLOCK, HOLDLOCK)
WHERE QuestionId = @QuestionId
  AND PortalId = @PortalId
  AND TabId = @TabId
  AND ModuleId = @ModuleId
  AND IsDeleted = 0
  AND IsApproved = 1;";
                        guard.Parameters.Add("@QuestionId", SqlDbType.Int).Value = question.QuestionId;
                        guard.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                        guard.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
                        guard.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
                        var rawStatus = guard.ExecuteScalar();
                        if (rawStatus == null || rawStatus == DBNull.Value)
                        {
                            transaction.Rollback();
                            return 0;
                        }
                        currentStatus = Convert.ToInt32(rawStatus);
                    }

                    if ((responseType == 1 && currentStatus != 0) || (responseType == 2 && currentStatus != 1))
                    {
                        transaction.Rollback();
                        return 0;
                    }

                    if (responseType == 2)
                    {
                        if (_settings.MaximumFollowUpQuestions <= 0)
                        {
                            transaction.Rollback();
                            return 0;
                        }

                        using (var countCommand = connection.CreateCommand())
                        {
                            countCommand.Transaction = transaction;
                            countCommand.CommandText = @"
SELECT COUNT(1)
FROM " + ResponsesTable + @" WITH (UPDLOCK, HOLDLOCK)
WHERE QuestionId = @QuestionId
  AND PortalId = @PortalId
  AND TabId = @TabId
  AND ModuleId = @ModuleId
  AND IsDeleted = 0
  AND ResponseType = 2;";
                            countCommand.Parameters.Add("@QuestionId", SqlDbType.Int).Value = question.QuestionId;
                            countCommand.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                            countCommand.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
                            countCommand.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
                            if (Convert.ToInt32(countCommand.ExecuteScalar()) >= _settings.MaximumFollowUpQuestions)
                            {
                                transaction.Rollback();
                                return 0;
                            }
                        }

                        using (var pending = connection.CreateCommand())
                        {
                            pending.Transaction = transaction;
                            pending.CommandText = @"
SELECT COUNT(1)
FROM " + ResponsesTable + @" WITH (UPDLOCK, HOLDLOCK)
WHERE QuestionId = @QuestionId
  AND PortalId = @PortalId
  AND IsDeleted = 0
  AND IsApproved = 0
  AND ResponseType = 2;";
                            pending.Parameters.Add("@QuestionId", SqlDbType.Int).Value = question.QuestionId;
                            pending.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                            if (Convert.ToInt32(pending.ExecuteScalar()) > 0)
                            {
                                transaction.Rollback();
                                return 0;
                            }
                        }
                    }

                    int responseId;
                    using (var command = connection.CreateCommand())
                    {
                        command.Transaction = transaction;
                        command.CommandText = @"
INSERT INTO " + ResponsesTable + @"
(QuestionId, PortalId, TabId, ModuleId, ResponseType, UserId, DisplayName, ResponseText, GuestRateLimitKey,
 IsApproved, IsDeleted, IsLanguageFlagged, IsRichText, CreatedOnDate, CreatedByUserId)
VALUES
(@QuestionId, @PortalId, @TabId, @ModuleId, @ResponseType, @UserId, @DisplayName, @ResponseText, @GuestRateLimitKey,
 @IsApproved, 0, @IsLanguageFlagged, @IsRichText, GETUTCDATE(), @CreatedByUserId);
SELECT CAST(SCOPE_IDENTITY() AS INT);";
                        command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = question.QuestionId;
                        command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                        command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
                        command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
                        command.Parameters.Add("@ResponseType", SqlDbType.TinyInt).Value = responseType;
                        command.Parameters.Add("@UserId", SqlDbType.Int).Value = isGuest ? (object)DBNull.Value : UserId;
                        command.Parameters.Add("@DisplayName", SqlDbType.NVarChar, 100).Value = Truncate(displayName, 100);
                        command.Parameters.Add("@ResponseText", SqlDbType.NVarChar, responseType == 1 ? -1 : _settings.MaximumResponseLength).Value = text;
                        command.Parameters.Add("@GuestRateLimitKey", SqlDbType.NVarChar, 64).Value = isGuest ? (object)guestRateKey : DBNull.Value;
                        command.Parameters.Add("@IsApproved", SqlDbType.Bit).Value = approved;
                        command.Parameters.Add("@IsLanguageFlagged", SqlDbType.Bit).Value = languageFlagged;
                        command.Parameters.Add("@IsRichText", SqlDbType.Bit).Value = responseType == 1;
                        command.Parameters.Add("@CreatedByUserId", SqlDbType.Int).Value = isGuest ? (object)DBNull.Value : UserId;
                        responseId = Convert.ToInt32(command.ExecuteScalar());
                    }

                    if (approved)
                    {
                        using (var update = connection.CreateCommand())
                        {
                            update.Transaction = transaction;
                            update.CommandText = @"
UPDATE " + QuestionsTable + @"
SET QuestionStatus = @Status,
    LastModifiedOnDate = GETUTCDATE(),
    LastModifiedByUserId = @UserId
WHERE QuestionId = @QuestionId
  AND PortalId = @PortalId
  AND TabId = @TabId
  AND ModuleId = @ModuleId
  AND IsDeleted = 0;";
                            update.Parameters.Add("@Status", SqlDbType.TinyInt).Value = responseType == 1 ? 1 : 0;
                            update.Parameters.Add("@UserId", SqlDbType.Int).Value = UserId > 0 ? (object)UserId : DBNull.Value;
                            update.Parameters.Add("@QuestionId", SqlDbType.Int).Value = question.QuestionId;
                            update.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                            update.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
                            update.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
                            update.ExecuteNonQuery();
                        }
                    }

                    if (responseType == 1)
                    {
                        using (var deleteDraft = connection.CreateCommand())
                        {
                            deleteDraft.Transaction = transaction;
                            deleteDraft.CommandText = @"
DELETE FROM " + AnswerDraftsTable + @"
WHERE QuestionId = @QuestionId AND PortalId = @PortalId AND TabId = @TabId AND ModuleId = @ModuleId;";
                            deleteDraft.Parameters.Add("@QuestionId", SqlDbType.Int).Value = question.QuestionId;
                            deleteDraft.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                            deleteDraft.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
                            deleteDraft.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
                            deleteDraft.ExecuteNonQuery();
                        }
                    }

                    transaction.Commit();
                    return responseId;
                }
                catch
                {
                    try { transaction.Rollback(); } catch { }
                    throw;
                }
            }
        }
    }

    private AnswerDraftRow GetAnswerDraft(int questionId)
    {
        if (questionId <= 0 || !CanManagePortalQandA()) return null;
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT TOP 1 DraftHtml, CreatedOnDate, ModifiedOnDate
FROM " + AnswerDraftsTable + @"
WHERE QuestionId = @QuestionId AND PortalId = @PortalId AND TabId = @TabId AND ModuleId = @ModuleId;";
            command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = questionId;
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
            command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                if (!reader.Read()) return null;
                return new AnswerDraftRow {
                    DraftHtml = Convert.ToString(reader["DraftHtml"]),
                    CreatedOnDate = Convert.ToDateTime(reader["CreatedOnDate"]),
                    ModifiedOnDate = Convert.ToDateTime(reader["ModifiedOnDate"])
                };
            }
        }
    }

    private bool SaveAnswerDraft(QuestionRow question, string cleanHtml)
    {
        if (question == null || question.QuestionId <= 0 || !CanManagePortalQandA()) return false;
        using (var connection = new SqlConnection(ConnectionString))
        {
            connection.Open();
            using (var transaction = connection.BeginTransaction(IsolationLevel.Serializable))
            {
                try
                {
                    using (var guard = connection.CreateCommand())
                    {
                        guard.Transaction = transaction;
                        guard.CommandText = @"
SELECT COUNT(1)
FROM " + QuestionsTable + @" WITH (UPDLOCK, HOLDLOCK)
WHERE QuestionId=@QuestionId AND PortalId=@PortalId AND TabId=@TabId AND ModuleId=@ModuleId
  AND IsDeleted=0 AND IsApproved=1 AND QuestionStatus=0;";
                        guard.Parameters.Add("@QuestionId", SqlDbType.Int).Value = question.QuestionId;
                        guard.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                        guard.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
                        guard.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
                        if (Convert.ToInt32(guard.ExecuteScalar()) != 1)
                        {
                            transaction.Rollback();
                            return false;
                        }
                    }

                    using (var command = connection.CreateCommand())
                    {
                        command.Transaction = transaction;
                        command.CommandText = @"
UPDATE " + AnswerDraftsTable + @"
SET DraftHtml=@DraftHtml, UserId=@UserId, ModifiedOnDate=GETUTCDATE()
WHERE QuestionId=@QuestionId AND PortalId=@PortalId AND TabId=@TabId AND ModuleId=@ModuleId;
IF @@ROWCOUNT = 0
BEGIN
    INSERT INTO " + AnswerDraftsTable + @"
    (QuestionId, PortalId, TabId, ModuleId, UserId, DraftHtml, CreatedOnDate, ModifiedOnDate)
    VALUES (@QuestionId, @PortalId, @TabId, @ModuleId, @UserId, @DraftHtml, GETUTCDATE(), GETUTCDATE());
END";
                        command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = question.QuestionId;
                        command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                        command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
                        command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
                        command.Parameters.Add("@UserId", SqlDbType.Int).Value = UserId;
                        command.Parameters.Add("@DraftHtml", SqlDbType.NVarChar, -1).Value = cleanHtml ?? String.Empty;
                        command.ExecuteNonQuery();
                    }
                    transaction.Commit();
                    return true;
                }
                catch
                {
                    try { transaction.Rollback(); } catch { }
                    throw;
                }
            }
        }
    }

    private string SanitizeMinistryAnswerHtml(string html)
    {
        if (String.IsNullOrWhiteSpace(html)) return String.Empty;

        // DNN's configured editor is available only to authenticated administrators here.
        // NoScripting plus the additional deny-list below preserves normal formatting but removes active content.
        var filtered = new PortalSecurity().InputFilter(html, PortalSecurity.FilterFlag.NoScripting);
        var options = RegexOptions.IgnoreCase | RegexOptions.Singleline | RegexOptions.CultureInvariant;

        filtered = Regex.Replace(filtered, @"<!--.*?-->", String.Empty, options);
        filtered = Regex.Replace(filtered, @"<\s*(script|style|iframe|object|embed|form|input|button|textarea|select|option|meta|link|base|svg|math|video|audio|source)\b[^>]*>.*?<\s*/\s*\1\s*>", String.Empty, options);
        filtered = Regex.Replace(filtered, @"<\s*/?\s*(script|style|iframe|object|embed|form|input|button|textarea|select|option|meta|link|base|svg|math|video|audio|source)\b[^>]*>", String.Empty, options);
        filtered = Regex.Replace(filtered, @"\s+on[a-z0-9_-]+\s*=\s*(?:""[^""]*""|'[^']*'|[^\s>]+)", String.Empty, options);
        filtered = Regex.Replace(filtered, @"\s+(style|srcdoc|formaction|target)\s*=\s*(?:""[^""]*""|'[^']*'|[^\s>]+)", String.Empty, options);
        filtered = Regex.Replace(filtered, @"\s+(href|src)\s*=\s*([""'])\s*(?:javascript|vbscript|data)\s*:[^""']*\2", String.Empty, options);
        filtered = Regex.Replace(filtered, @"\s+(href|src)\s*=\s*(?:javascript|vbscript|data)\s*:[^\s>]+", String.Empty, options);

        return filtered.Trim();
    }

    private string RichTextToPlainText(string html)
    {
        if (String.IsNullOrWhiteSpace(html)) return String.Empty;
        var text = html;
        text = Regex.Replace(text, @"<\s*br\s*/?\s*>", "\n", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"<\s*li\b[^>]*>", "- ", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"<\s*/\s*(p|div|li|h[1-6]|blockquote|tr)\s*>", "\n", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"<[^>]+>", String.Empty, RegexOptions.Singleline);
        text = HttpUtility.HtmlDecode(text);
        text = text.Replace("\r\n", "\n").Replace("\r", "\n");
        text = Regex.Replace(text, @"[ \t]+", " ");
        text = Regex.Replace(text, @" *\n *", "\n");
        text = Regex.Replace(text, @"\n{3,}", "\n\n");
        return text.Trim();
    }

    protected string RenderResponseText(object dataItem)
    {
        var row = dataItem as ResponseRow;
        if (row == null) return String.Empty;
        if (row.ResponseType == 1 && row.IsRichText)
        {
            return SanitizeMinistryAnswerHtml(row.ResponseText);
        }
        return HttpUtility.HtmlEncode(row.ResponseText ?? String.Empty);
    }

    protected string ResponseTextCss(object dataItem)
    {
        var row = dataItem as ResponseRow;
        return row != null && row.ResponseType == 1 && row.IsRichText ? " jqa-rich-response-text" : String.Empty;
    }

    private void UpdateQuestionStatus(int questionId, int status)
    {
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
UPDATE " + QuestionsTable + @"
SET QuestionStatus = @Status,
    LastModifiedOnDate = GETUTCDATE(),
    LastModifiedByUserId = @UserId
WHERE QuestionId = @QuestionId AND PortalId = @PortalId AND TabId = @TabId AND ModuleId = @ModuleId AND IsDeleted = 0;";
            command.Parameters.Add("@Status", SqlDbType.TinyInt).Value = status;
            command.Parameters.Add("@UserId", SqlDbType.Int).Value = UserId > 0 ? (object)UserId : DBNull.Value;
            command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = questionId;
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
            command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
            connection.Open();
            command.ExecuteNonQuery();
        }
    }

    private void BindQuestions()
    {
        var questions = new List<QuestionRow>();
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT QuestionId, UserId, DisplayName, GuestConversationTokenHash, QuestionTitle, QuestionText, QuestionStatus,
       IsLanguageFlagged, CreatedOnDate
FROM " + QuestionsTable + @"
WHERE PortalId = @PortalId AND TabId = @TabId AND ModuleId = @ModuleId AND IsDeleted = 0 AND IsApproved = 1"
                + (_focusedAnswerMode && _focusedAnswerQuestionId.HasValue ? " AND QuestionId = @FocusedQuestionId" : String.Empty)
                + @"
ORDER BY CreatedOnDate DESC, QuestionId DESC;";
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
            command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
            if (_focusedAnswerMode && _focusedAnswerQuestionId.HasValue)
            {
                command.Parameters.Add("@FocusedQuestionId", SqlDbType.Int).Value = _focusedAnswerQuestionId.Value;
            }
            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                while (reader.Read())
                {
                    questions.Add(new QuestionRow {
                        QuestionId = Convert.ToInt32(reader["QuestionId"]),
                        UserId = reader["UserId"] == DBNull.Value ? (int?)null : Convert.ToInt32(reader["UserId"]),
                        DisplayName = Convert.ToString(reader["DisplayName"]),
                        GuestConversationTokenHash = reader["GuestConversationTokenHash"] == DBNull.Value ? String.Empty : Convert.ToString(reader["GuestConversationTokenHash"]),
                        QuestionTitle = Convert.ToString(reader["QuestionTitle"]),
                        QuestionText = Convert.ToString(reader["QuestionText"]),
                        QuestionStatus = Convert.ToInt32(reader["QuestionStatus"]),
                        IsLanguageFlagged = Convert.ToBoolean(reader["IsLanguageFlagged"]),
                        CreatedOnDate = Convert.ToDateTime(reader["CreatedOnDate"])
                    });
                }
            }
        }

        foreach (var question in questions) question.Responses = GetResponses(question.QuestionId);
        rptQuestions.DataSource = questions;
        rptQuestions.DataBind();
        pnlNoQuestions.Visible = questions.Count == 0;
    }

    private List<ResponseRow> GetResponses(int questionId)
    {
        var rows = new List<ResponseRow>();
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT ResponseId, ResponseType, UserId, DisplayName, ResponseText, IsLanguageFlagged, IsRichText, CreatedOnDate
FROM " + ResponsesTable + @"
WHERE QuestionId = @QuestionId AND PortalId = @PortalId AND TabId = @TabId AND ModuleId = @ModuleId
  AND IsDeleted = 0 AND IsApproved = 1
ORDER BY CreatedOnDate ASC, ResponseId ASC;";
            command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = questionId;
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
            command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                while (reader.Read())
                {
                    rows.Add(new ResponseRow {
                        ResponseId = Convert.ToInt32(reader["ResponseId"]),
                        ResponseType = Convert.ToInt32(reader["ResponseType"]),
                        UserId = reader["UserId"] == DBNull.Value ? (int?)null : Convert.ToInt32(reader["UserId"]),
                        DisplayName = Convert.ToString(reader["DisplayName"]),
                        ResponseText = Convert.ToString(reader["ResponseText"]),
                        IsLanguageFlagged = Convert.ToBoolean(reader["IsLanguageFlagged"]),
                        IsRichText = Convert.ToBoolean(reader["IsRichText"]),
                        CreatedOnDate = Convert.ToDateTime(reader["CreatedOnDate"])
                    });
                }
            }
        }
        return rows;
    }

    private QuestionRow GetQuestion(int questionId, bool approvedOnly)
    {
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT TOP 1 QuestionId, UserId, DisplayName, GuestEmailEncrypted, GuestConversationTokenHash, QuestionTitle, QuestionText, QuestionStatus,
       IsLanguageFlagged, CreatedOnDate
FROM " + QuestionsTable + @"
WHERE QuestionId = @QuestionId AND PortalId = @PortalId AND TabId = @TabId AND ModuleId = @ModuleId
  AND IsDeleted = 0" + (approvedOnly ? " AND IsApproved = 1" : String.Empty) + ";";
            command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = questionId;
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
            command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                if (!reader.Read()) return null;
                return new QuestionRow {
                    QuestionId = Convert.ToInt32(reader["QuestionId"]),
                    UserId = reader["UserId"] == DBNull.Value ? (int?)null : Convert.ToInt32(reader["UserId"]),
                    DisplayName = Convert.ToString(reader["DisplayName"]),
                    GuestEmailEncrypted = reader["GuestEmailEncrypted"] == DBNull.Value ? String.Empty : Convert.ToString(reader["GuestEmailEncrypted"]),
                    GuestConversationTokenHash = reader["GuestConversationTokenHash"] == DBNull.Value ? String.Empty : Convert.ToString(reader["GuestConversationTokenHash"]),
                    QuestionTitle = Convert.ToString(reader["QuestionTitle"]),
                    QuestionText = Convert.ToString(reader["QuestionText"]),
                    QuestionStatus = Convert.ToInt32(reader["QuestionStatus"]),
                    IsLanguageFlagged = Convert.ToBoolean(reader["IsLanguageFlagged"]),
                    CreatedOnDate = Convert.ToDateTime(reader["CreatedOnDate"])
                };
            }
        }
    }

    protected bool CanShowAnswerButton(object dataItem)
    {
        var question = dataItem as QuestionRow;
        return question != null && question.QuestionStatus == 0 && CanManagePortalQandA();
    }

    protected bool CanShowFollowUpButton(object dataItem)
    {
        var question = dataItem as QuestionRow;
        return question != null && question.QuestionStatus == 1 && CanQuestionerFollowUp(question);
    }

    protected string QuestionCss(object dataItem)
    {
        var question = dataItem as QuestionRow;
        if (question != null && _expandedQuestionId.HasValue && _expandedQuestionId.Value == question.QuestionId)
            return "jqa-question jqa-question-expanded";
        return "jqa-question";
    }

    protected string QuestionExpandedValue(object dataItem)
    {
        var question = dataItem as QuestionRow;
        return question != null && _expandedQuestionId.HasValue && _expandedQuestionId.Value == question.QuestionId
            ? "true"
            : "false";
    }

    protected string StatusText(object value)
    {
        var status = Convert.ToInt32(value);
        if (status == 1) return "Answered";
        if (status == 2) return "Closed";
        return "Awaiting Answer";
    }

    protected string StatusCss(object value)
    {
        var status = Convert.ToInt32(value);
        if (status == 1) return "jqa-status jqa-status-answered";
        if (status == 2) return "jqa-status jqa-status-closed";
        return "jqa-status jqa-status-awaiting";
    }

    protected string ResponseRole(object value)
    {
        return Convert.ToInt32(value) == 1 ? "Ministry Answer" : "Questioner Follow-up";
    }

    protected string ResponseCss(object value)
    {
        return Convert.ToInt32(value) == 1 ? "jqa-response jqa-ministry-answer" : "jqa-response jqa-questioner-followup";
    }

    protected string Encode(object value) { return HttpUtility.HtmlEncode(Convert.ToString(value)); }
    protected string FormatDate(object value)
    {
        if (value == null || value == DBNull.Value) return String.Empty;
        return Convert.ToDateTime(value).ToLocalTime().ToString("d MMM yyyy, h:mm tt");
    }

    private bool CanQuestionerFollowUp(QuestionRow question)
    {
        if (question == null || question.QuestionStatus != 1) return false;
        if (!IsOriginalQuestioner(question)) return false;
        if (HasPendingQuestionerFollowUp(question.QuestionId)) return false;
        if (HasReachedFollowUpLimit(question.QuestionId)) return false;
        return true;
    }

    private bool IsOriginalQuestioner(QuestionRow question)
    {
        if (question == null) return false;
        if (question.UserId.HasValue && question.UserId.Value > 0)
            return UserInfo != null && UserInfo.UserID == question.UserId.Value;
        return ValidateConversationCookie(question);
    }

    private bool HasPendingQuestionerFollowUp(int questionId)
    {
        if (questionId <= 0) return false;
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT COUNT(1)
FROM " + ResponsesTable + @"
WHERE QuestionId = @QuestionId
  AND PortalId = @PortalId
  AND TabId = @TabId
  AND ModuleId = @ModuleId
  AND IsDeleted = 0
  AND IsApproved = 0
  AND ResponseType = 2;";
            command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = questionId;
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
            command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
            connection.Open();
            return Convert.ToInt32(command.ExecuteScalar()) > 0;
        }
    }

    private int GetQuestionerFollowUpCount(int questionId)
    {
        if (questionId <= 0) return 0;
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT COUNT(1)
FROM " + ResponsesTable + @"
WHERE QuestionId = @QuestionId
  AND PortalId = @PortalId
  AND TabId = @TabId
  AND ModuleId = @ModuleId
  AND IsDeleted = 0
  AND ResponseType = 2;";
            command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = questionId;
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
            command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
            connection.Open();
            return Convert.ToInt32(command.ExecuteScalar());
        }
    }

    private bool HasReachedFollowUpLimit(int questionId)
    {
        var maximum = _settings == null ? 4 : _settings.MaximumFollowUpQuestions;
        if (maximum <= 0) return true;
        return GetQuestionerFollowUpCount(questionId) >= maximum;
    }

    protected bool ShouldShowFollowUpLimitMessage(object dataItem)
    {
        var question = dataItem as QuestionRow;
        return question != null
            && question.QuestionStatus == 1
            && IsOriginalQuestioner(question)
            && HasReachedFollowUpLimit(question.QuestionId);
    }

    protected string GetFollowUpLimitMessage()
    {
        var maximum = _settings == null ? 4 : _settings.MaximumFollowUpQuestions;
        if (maximum <= 0)
            return "Follow-up questions are currently disabled for this Q&A.";
        return "The maximum of " + maximum + " follow-up " + (maximum == 1 ? "question has" : "questions have") + " been reached for this conversation. If you have another question, please begin a new Q&A.";
    }

    private bool CanManagePortalQandA()
    {
        if (UserInfo == null) return false;
        if (UserInfo.IsSuperUser) return true;
        var role = PortalSettings == null ? String.Empty : (PortalSettings.AdministratorRoleName ?? String.Empty).Trim();
        return !String.IsNullOrWhiteSpace(role) && UserInfo.IsInRole(role);
    }

    private void SetResponseContext(QuestionRow question, bool answer)
    {
        hdnResponseQuestionId.Value = question.QuestionId.ToString();
        hdnResponseMode.Value = answer ? "answer" : "followup";
        litResponseHeading.Text = answer ? "Answer this question" : "Ask a follow-up";
        litResponseQuestionTitle.Text = HttpUtility.HtmlEncode(question.QuestionTitle);
        btnSubmitResponse.Text = answer ? "Publish Answer" : "Submit Follow-up";
        btnSaveDraft.Visible = answer && CanManagePortalQandA();
        btnSaveDraft.OnClientClick = String.Empty;
        btnSubmitResponse.OnClientClick = String.Empty;
        pnlPlainResponseEditor.Visible = !answer;
        pnlRichAnswerEditor.Visible = answer;
        pnlResponseForm.Visible = true;
        txtResponse.Text = String.Empty;
        litDraftStatus.Text = String.Empty;

        if (answer)
        {
                        var draft = GetAnswerDraft(question.QuestionId);
            if (txtAnswerEditor != null) txtAnswerEditor.Text = draft == null ? String.Empty : draft.DraftHtml;
            if (draft != null)
            {
                litResponseHeading.Text = "Resume answer draft";
                litDraftStatus.Text = "Draft saved " + HttpUtility.HtmlEncode(draft.ModifiedOnDate.ToLocalTime().ToString("d MMM yyyy, h:mm tt")) + ".";
            }
        }

        EnsureCaptchaChallenge();
    }

    private void ClearResponseContext()
    {
        hdnResponseQuestionId.Value = String.Empty;
        hdnResponseMode.Value = String.Empty;
        txtResponse.Text = String.Empty;
        if (txtAnswerEditor != null) txtAnswerEditor.Text = String.Empty;
        litDraftStatus.Text = String.Empty;
        btnSaveDraft.Visible = false;
        pnlPlainResponseEditor.Visible = true;
        pnlRichAnswerEditor.Visible = false;
        txtResponseCaptcha.Text = String.Empty;
        pnlResponseForm.Visible = false;
    }

    private void ShowResponseMessageAndRefocus(string message, int questionId)
    {
        ShowMessage(message, false);
        if (String.Equals(hdnResponseMode.Value, "answer", StringComparison.Ordinal))
            RegisterAnswerContextFocusScript(questionId);
        else
            RegisterFollowUpContextFocusScript(questionId);
    }

    private void ClearQuestionForm()
    {
        txtQuestionTitle.Text = String.Empty;
        txtQuestion.Text = String.Empty;
        txtGuestName.Text = String.Empty;
        txtGuestEmail.Text = String.Empty;
        txtQuestionCaptcha.Text = String.Empty;
        txtWebsite.Text = String.Empty;
    }

    private bool CaptchaAppliesToCurrentUser()
    {
        return _settings != null && _settings.EnableCaptcha && !CanManagePortalQandA();
    }

    private void EnsureCaptchaChallenge()
    {
        if (CaptchaAppliesToCurrentUser() && ViewState[CaptchaAnswerKey] == null) GenerateCaptchaChallenge();
    }

    private void GenerateCaptchaChallenge()
    {
        if (!CaptchaAppliesToCurrentUser())
        {
            ViewState[CaptchaAnswerKey] = null;
            litQuestionCaptcha.Text = String.Empty;
            litResponseCaptcha.Text = String.Empty;
            return;
        }
        var random = new Random(unchecked(Environment.TickCount + ModuleId * 31 + UserId * 17));
        var left = random.Next(2, 10);
        var right = random.Next(1, 9);
        ViewState[CaptchaAnswerKey] = left + right;
        var prompt = left + " + " + right + " =";
        litQuestionCaptcha.Text = prompt;
        litResponseCaptcha.Text = prompt;
        txtQuestionCaptcha.Text = String.Empty;
        txtResponseCaptcha.Text = String.Empty;
    }

    private bool ValidateCaptcha(System.Web.UI.WebControls.TextBox box, out string errorMessage)
    {
        errorMessage = String.Empty;
        if (!CaptchaAppliesToCurrentUser()) return true;
        int expected;
        if (ViewState[CaptchaAnswerKey] == null || !Int32.TryParse(Convert.ToString(ViewState[CaptchaAnswerKey]), out expected))
        {
            errorMessage = "Please answer the anti-spam question.";
            return false;
        }
        int supplied;
        if (!Int32.TryParse((box.Text ?? String.Empty).Trim(), out supplied) || supplied != expected)
        {
            errorMessage = "The anti-spam answer was not correct. Please try again.";
            return false;
        }
        return true;
    }

    private bool HasActiveQuestionForCurrentQuestioner(bool isGuest, string guestRateKey)
    {
        if (!isGuest)
        {
            if (UserInfo == null || UserInfo.UserID <= 0) return false;
            using (var connection = new SqlConnection(ConnectionString))
            using (var command = connection.CreateCommand())
            {
                command.CommandText = @"
SELECT COUNT(1)
FROM " + QuestionsTable + @" q
WHERE q.PortalId = @PortalId
  AND q.UserId = @UserId
  AND q.IsDeleted = 0
  AND q.QuestionStatus <> 2
  AND (q.IsApproved = 0
       OR q.QuestionStatus = 0
       OR EXISTS (
            SELECT 1 FROM " + ResponsesTable + @" r
            WHERE r.QuestionId = q.QuestionId
              AND r.PortalId = q.PortalId
              AND r.IsDeleted = 0
              AND r.IsApproved = 0
              AND r.ResponseType = 2));";
                command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                command.Parameters.Add("@UserId", SqlDbType.Int).Value = UserInfo.UserID;
                connection.Open();
                return Convert.ToInt32(command.ExecuteScalar()) > 0;
            }
        }

        if (String.IsNullOrWhiteSpace(guestRateKey)) return false;

        using (var connection = new SqlConnection(ConnectionString))
        {
            connection.Open();
            using (var direct = connection.CreateCommand())
            {
                direct.CommandText = @"
SELECT COUNT(1)
FROM " + QuestionsTable + @" q
WHERE q.PortalId = @PortalId
  AND q.UserId IS NULL
  AND q.GuestRateLimitKey = @GuestRateLimitKey
  AND q.IsDeleted = 0
  AND q.QuestionStatus <> 2
  AND (q.IsApproved = 0
       OR q.QuestionStatus = 0
       OR EXISTS (
            SELECT 1 FROM " + ResponsesTable + @" r
            WHERE r.QuestionId = q.QuestionId
              AND r.PortalId = q.PortalId
              AND r.IsDeleted = 0
              AND r.IsApproved = 0
              AND r.ResponseType = 2));";
                direct.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                direct.Parameters.Add("@GuestRateLimitKey", SqlDbType.NVarChar, 64).Value = guestRateKey;
                if (Convert.ToInt32(direct.ExecuteScalar()) > 0) return true;
            }

            // Compatibility fallback for guest questions created before the persistent
            // browser identity was introduced. A valid per-question conversation cookie
            // still proves that this browser owns the active question.
            using (var legacy = connection.CreateCommand())
            {
                legacy.CommandText = @"
SELECT TOP 100 q.QuestionId, q.ModuleId, q.GuestConversationTokenHash
FROM " + QuestionsTable + @" q
WHERE q.PortalId = @PortalId
  AND q.UserId IS NULL
  AND q.IsDeleted = 0
  AND q.QuestionStatus <> 2
  AND q.CreatedOnDate >= DATEADD(DAY, -180, GETUTCDATE())
  AND (q.IsApproved = 0
       OR q.QuestionStatus = 0
       OR EXISTS (
            SELECT 1 FROM " + ResponsesTable + @" r
            WHERE r.QuestionId = q.QuestionId
              AND r.PortalId = q.PortalId
              AND r.IsDeleted = 0
              AND r.IsApproved = 0
              AND r.ResponseType = 2))
ORDER BY q.CreatedOnDate DESC;";
                legacy.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                using (var reader = legacy.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        var questionId = Convert.ToInt32(reader["QuestionId"]);
                        var moduleId = Convert.ToInt32(reader["ModuleId"]);
                        var storedHash = reader["GuestConversationTokenHash"] == DBNull.Value ? String.Empty : Convert.ToString(reader["GuestConversationTokenHash"]);
                        if (ValidateConversationCookie(questionId, moduleId, storedHash)) return true;
                    }
                }
            }
        }
        return false;
    }

    private bool CheckRateLimit(bool isGuest, string guestRateKey, out string errorMessage)
    {
        errorMessage = String.Empty;
        if (!_settings.EnableRateLimiting || CanManagePortalQandA()) return true;

        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT COUNT(1) AS RecentPostCount,
       ISNULL(DATEDIFF(SECOND, MAX(CreatedOnDate), GETUTCDATE()), 999999) AS SecondsSinceLastPost
FROM (
    SELECT CreatedOnDate, CreatedByUserId, GuestRateLimitKey, IsDeleted FROM " + QuestionsTable + @" WHERE PortalId = @PortalId
    UNION ALL
    SELECT CreatedOnDate, CreatedByUserId, GuestRateLimitKey, IsDeleted FROM " + ResponsesTable + @" WHERE PortalId = @PortalId
) AS Posts
WHERE IsDeleted = 0
  AND ((@IsGuest = 0 AND CreatedByUserId = @UserId) OR (@IsGuest = 1 AND GuestRateLimitKey = @GuestRateLimitKey))
  AND CreatedOnDate >= DATEADD(MINUTE, -@WindowMinutes, GETUTCDATE());";
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@IsGuest", SqlDbType.Bit).Value = isGuest;
            command.Parameters.Add("@UserId", SqlDbType.Int).Value = UserId;
            command.Parameters.Add("@GuestRateLimitKey", SqlDbType.NVarChar, 64).Value = isGuest ? (object)(guestRateKey ?? String.Empty) : DBNull.Value;
            command.Parameters.Add("@WindowMinutes", SqlDbType.Int).Value = _settings.RateLimitWindowMinutes;
            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                if (reader.Read())
                {
                    var count = Convert.ToInt32(reader["RecentPostCount"]);
                    var seconds = Convert.ToInt32(reader["SecondsSinceLastPost"]);
                    if (_settings.RateLimitSeconds > 0 && seconds < _settings.RateLimitSeconds)
                    {
                        var wait = _settings.RateLimitSeconds - seconds;
                        errorMessage = "Please wait " + wait + " more second" + (wait == 1 ? "" : "s") + " before posting again.";
                        return false;
                    }
                    if (count >= _settings.RateLimitMaxPosts)
                    {
                        errorMessage = "You have reached the posting limit for this time window. Please try again later.";
                        return false;
                    }
                }
            }
        }
        return true;
    }

    private bool ContainsBlockedLanguage(string value)
    {
        if (!_settings.EnableLanguageFilter || String.IsNullOrWhiteSpace(value) || String.IsNullOrWhiteSpace(_settings.BlockedLanguageTerms)) return false;
        var searchable = " " + NormalizeLanguageFilterText(value) + " ";
        var terms = _settings.BlockedLanguageTerms.Replace("\r\n", "\n").Replace('\r', '\n').Split(new[] {'\n'}, StringSplitOptions.RemoveEmptyEntries);
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var count = 0;
        foreach (var raw in terms)
        {
            var term = (raw ?? String.Empty).Trim();
            if (term.Length > MaximumBlockedTermLength) term = term.Substring(0, MaximumBlockedTermLength);
            term = NormalizeLanguageFilterText(term);
            if (term.Length == 0 || !seen.Add(term)) continue;
            count++;
            if (searchable.IndexOf(" " + term + " ", StringComparison.Ordinal) >= 0) return true;
            if (count >= MaximumBlockedTermCount) break;
        }
        return false;
    }

    private static string NormalizeLanguageFilterText(string value)
    {
        if (String.IsNullOrWhiteSpace(value)) return String.Empty;
        string normalized;
        try { normalized = value.Normalize(NormalizationForm.FormKC).ToLowerInvariant(); }
        catch { normalized = value.ToLowerInvariant(); }
        var output = new StringBuilder(normalized.Length);
        var separator = true;
        foreach (var c in normalized)
        {
            if (Char.IsLetterOrDigit(c)) { output.Append(c); separator = false; }
            else if (!separator) { output.Append(' '); separator = true; }
        }
        return output.ToString().Trim();
    }

    private void EnsureSecurityToken() { EnsureSecurityToken(false); }
    private void EnsureSecurityToken(bool rotate)
    {
        if (Session == null) return;
        var token = rotate ? String.Empty : Convert.ToString(Session[SecurityTokenSessionKey]);
        if (String.IsNullOrWhiteSpace(token))
        {
            token = GenerateSecurityToken();
            Session[SecurityTokenSessionKey] = token;
        }
        hdnSecurityToken.Value = token;
    }

    private bool ValidateSecurityToken()
    {
        if (Session == null || hdnSecurityToken == null) return false;
        return SecureEquals(Convert.ToString(Session[SecurityTokenSessionKey]), hdnSecurityToken.Value);
    }

    private static string GenerateSecurityToken()
    {
        var bytes = new byte[32];
        using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
        return Convert.ToBase64String(bytes);
    }

    private static bool SecureEquals(string expected, string supplied)
    {
        if (String.IsNullOrEmpty(expected) || String.IsNullOrEmpty(supplied)) return false;
        var a = Encoding.UTF8.GetBytes(expected);
        var b = Encoding.UTF8.GetBytes(supplied);
        var diff = a.Length ^ b.Length;
        var length = Math.Max(a.Length, b.Length);
        for (var i = 0; i < length; i++)
        {
            var av = i < a.Length ? a[i] : (byte)0;
            var bv = i < b.Length ? b[i] : (byte)0;
            diff |= av ^ bv;
        }
        return diff == 0;
    }

    private string ComputeGuestEditTokenHash(string token)
    {
        if (String.IsNullOrWhiteSpace(token)) return String.Empty;
        var source = "JacarandaQAGuestEdit|" + PortalId + "|" + TabId + "|" + ModuleId + "|" + token;
        using (var sha = SHA256.Create()) return BytesToHex(sha.ComputeHash(Encoding.UTF8.GetBytes(source)));
    }

    private void SetGuestEditSession(int questionId, string token)
    {
        if (Session == null || questionId <= 0 || String.IsNullOrWhiteSpace(token)) return;
        Session[GuestEditQuestionSessionKey] = questionId.ToString();
        Session[GuestEditTokenSessionKey] = token;
    }

    private void ClearGuestEditSession()
    {
        if (Session == null) return;
        Session.Remove(GuestEditQuestionSessionKey);
        Session.Remove(GuestEditTokenSessionKey);
    }

    private bool TryGetGuestEditSession(out int questionId, out string tokenHash)
    {
        questionId = 0;
        tokenHash = String.Empty;
        if (Session == null) return false;
        if (UserInfo != null && UserInfo.UserID > 0) return false;

        var rawQuestionId = Convert.ToString(Session[GuestEditQuestionSessionKey]);
        var token = Convert.ToString(Session[GuestEditTokenSessionKey]);
        if (!Int32.TryParse(rawQuestionId, out questionId) || questionId <= 0 || String.IsNullOrWhiteSpace(token))
        {
            questionId = 0;
            return false;
        }

        tokenHash = ComputeGuestEditTokenHash(token);
        return !String.IsNullOrWhiteSpace(tokenHash);
    }

    private void LoadGuestCorrectionPanel()
    {
        pnlGuestCorrection.Visible = false;

        int questionId;
        string tokenHash;
        if (!TryGetGuestEditSession(out questionId, out tokenHash)) return;

        string title;
        string text;
        DateTime createdOnUtc;
        string errorMessage;
        if (!TryLoadGuestEditableQuestion(questionId, tokenHash, out title, out text, out createdOnUtc, out errorMessage))
        {
            ClearGuestEditSession();
            return;
        }

        hdnGuestEditQuestionId.Value = questionId.ToString();
        txtGuestEditTitle.Text = title;
        txtGuestEditQuestion.Text = text;
        pnlGuestCorrection.Visible = true;
        RegisterGuestCorrectionCountdownScript(createdOnUtc.AddMinutes(GuestEditWindowMinutes));
    }

    private bool TryLoadGuestEditableQuestion(
        int questionId,
        string tokenHash,
        out string title,
        out string text,
        out DateTime createdOnUtc,
        out string errorMessage)
    {
        title = String.Empty;
        text = String.Empty;
        createdOnUtc = DateTime.MinValue;
        errorMessage = "The 5-minute correction window is no longer available.";

        if (questionId <= 0 || String.IsNullOrWhiteSpace(tokenHash)) return false;

        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT TOP 1 QuestionTitle, QuestionText, CreatedOnDate
FROM " + QuestionsTable + @"
WHERE QuestionId = @QuestionId
  AND PortalId = @PortalId
  AND TabId = @TabId
  AND ModuleId = @ModuleId
  AND UserId IS NULL
  AND IsDeleted = 0
  AND IsApproved = 0
  AND GuestEditTokenHash = @GuestEditTokenHash
  AND CreatedOnDate >= DATEADD(MINUTE, -@EditWindowMinutes, GETUTCDATE());";
            command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = questionId;
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
            command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
            command.Parameters.Add("@GuestEditTokenHash", SqlDbType.NVarChar, 64).Value = tokenHash;
            command.Parameters.Add("@EditWindowMinutes", SqlDbType.Int).Value = GuestEditWindowMinutes;

            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                if (!reader.Read()) return false;
                title = Convert.ToString(reader["QuestionTitle"]);
                text = Convert.ToString(reader["QuestionText"]);
                createdOnUtc = DateTime.SpecifyKind(Convert.ToDateTime(reader["CreatedOnDate"]), DateTimeKind.Utc);
                return true;
            }
        }
    }

    private void RegisterGuestCorrectionCountdownForCurrentQuestion(int questionId, string tokenHash)
    {
        string currentTitle;
        string currentText;
        DateTime createdOnUtc;
        string errorMessage;
        if (TryLoadGuestEditableQuestion(questionId, tokenHash, out currentTitle, out currentText, out createdOnUtc, out errorMessage))
        {
            RegisterGuestCorrectionCountdownScript(createdOnUtc.AddMinutes(GuestEditWindowMinutes));
        }
    }

    protected void btnSaveGuestCorrection_Click(object sender, EventArgs e)
    {
        try
        {
            _settings = ReadPortalSettings();

            if (!ValidateSecurityToken())
            {
                ShowMessage("The form security token expired. Please refresh the page and try again.", false);
                return;
            }

            int sessionQuestionId;
            string tokenHash;
            int questionId;
            if (!TryGetGuestEditSession(out sessionQuestionId, out tokenHash)
                || !Int32.TryParse((hdnGuestEditQuestionId.Value ?? String.Empty).Trim(), out questionId)
                || questionId <= 0
                || questionId != sessionQuestionId)
            {
                ClearGuestEditSession();
                pnlGuestCorrection.Visible = false;
                ShowMessage("The 5-minute correction window is no longer available.", false);
                return;
            }

            var title = NormalizeSingleLineText(txtGuestEditTitle.Text);
            var text = (txtGuestEditQuestion.Text ?? String.Empty).Trim();
            if (title.Length < 3 || title.Length > MaximumQuestionTitleLength)
            {
                pnlGuestCorrection.Visible = true;
                ShowMessage("Please enter a question title between 3 and 250 characters.", false);
                RegisterGuestCorrectionCountdownForCurrentQuestion(questionId, tokenHash);
                RegisterGuestCorrectionFocusScript();
                return;
            }
            if (text.Length < MinimumQuestionLength || text.Length > _settings.MaximumQuestionLength)
            {
                pnlGuestCorrection.Visible = true;
                ShowMessage("Please enter a question between " + MinimumQuestionLength + " and " + _settings.MaximumQuestionLength + " characters.", false);
                RegisterGuestCorrectionCountdownForCurrentQuestion(questionId, tokenHash);
                RegisterGuestCorrectionFocusScript();
                return;
            }

            var languageFlagged = ContainsBlockedLanguage(title + " " + text);
            if (!TryUpdateGuestQuestion(questionId, tokenHash, title, text, languageFlagged))
            {
                ClearGuestEditSession();
                pnlGuestCorrection.Visible = false;
                ShowMessage("The question could not be corrected. The 5-minute window may have expired or the question may already have been approved.", false);
                return;
            }

            ClearGuestEditSession();
            pnlGuestCorrection.Visible = false;
            CompletePublicPost("Correction saved. Your question is now awaiting moderation. The correction opportunity is now closed.", true, 0);
            return;
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            ShowMessage("The question could not be corrected. Please try again.", false);
        }
    }

    private bool TryUpdateGuestQuestion(int questionId, string tokenHash, string title, string text, bool languageFlagged)
    {
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
UPDATE " + QuestionsTable + @"
SET QuestionTitle = @QuestionTitle,
    QuestionText = @QuestionText,
    IsLanguageFlagged = @IsLanguageFlagged,
    EditedOnDate = GETUTCDATE(),
    EditedByUserId = NULL,
    LastModifiedOnDate = GETUTCDATE(),
    LastModifiedByUserId = NULL,
    GuestEditTokenHash = NULL
WHERE QuestionId = @QuestionId
  AND PortalId = @PortalId
  AND TabId = @TabId
  AND ModuleId = @ModuleId
  AND UserId IS NULL
  AND IsDeleted = 0
  AND IsApproved = 0
  AND GuestEditTokenHash = @GuestEditTokenHash
  AND CreatedOnDate >= DATEADD(MINUTE, -@EditWindowMinutes, GETUTCDATE());";
            command.Parameters.Add("@QuestionTitle", SqlDbType.NVarChar, 250).Value = title;
            command.Parameters.Add("@QuestionText", SqlDbType.NVarChar, _settings.MaximumQuestionLength).Value = text;
            command.Parameters.Add("@IsLanguageFlagged", SqlDbType.Bit).Value = languageFlagged;
            command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = questionId;
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
            command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
            command.Parameters.Add("@GuestEditTokenHash", SqlDbType.NVarChar, 64).Value = tokenHash;
            command.Parameters.Add("@EditWindowMinutes", SqlDbType.Int).Value = GuestEditWindowMinutes;
            connection.Open();
            return command.ExecuteNonQuery() == 1;
        }
    }

    private void RegisterGuestCorrectionCountdownScript(DateTime expiresUtc)
    {
        if (Page == null) return;
        var remainingSeconds = Math.Max(0, (int)Math.Ceiling((expiresUtc - DateTime.UtcNow).TotalSeconds));
        var countdownId = HttpUtility.JavaScriptStringEncode(GuestCorrectionCountdownId);
        var buttonId = HttpUtility.JavaScriptStringEncode(btnSaveGuestCorrection.ClientID);
        var titleId = HttpUtility.JavaScriptStringEncode(txtGuestEditTitle.ClientID);
        var questionId = HttpUtility.JavaScriptStringEncode(txtGuestEditQuestion.ClientID);
        var script = @"
(function () {
    var remaining = " + remainingSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture) + @";
    var output = document.getElementById('" + countdownId + @"');
    var button = document.getElementById('" + buttonId + @"');
    var title = document.getElementById('" + titleId + @"');
    var question = document.getElementById('" + questionId + @"');
    function render() {
        if (!output) { return; }
        if (remaining <= 0) {
            output.textContent = 'Correction window ended';
            if (button) { button.disabled = true; button.setAttribute('aria-disabled', 'true'); }
            if (title) { title.disabled = true; }
            if (question) { question.disabled = true; }
            return;
        }
        var minutes = Math.floor(remaining / 60);
        var seconds = remaining % 60;
        output.textContent = minutes + ':' + (seconds < 10 ? '0' : '') + seconds;
        remaining -= 1;
        window.setTimeout(render, 1000);
    }
    render();
})();";
        RegisterStartupScript("JacarandaQandAGuestCorrectionCountdown_" + ModuleId, script);
    }

    private void RegisterGuestCorrectionFocusScript()
    {
        if (Page == null || pnlGuestCorrection == null) return;
        var targetId = HttpUtility.JavaScriptStringEncode(pnlGuestCorrection.ClientID);
        var script = @"
(function () {
    var target = document.getElementById('" + targetId + @"');
    if (!target) { return; }
    window.setTimeout(function () {
        try {
            target.setAttribute('tabindex', '-1');
            target.scrollIntoView({ behavior: 'auto', block: 'start' });
            target.focus();
        } catch (e) { try { target.scrollIntoView(true); } catch (ignore) { } }
    }, 50);
})();";
        RegisterStartupScript("JacarandaQandAGuestCorrectionFocus_" + ModuleId, script);
    }

    private string ComputeConversationTokenHash(string token)
    {
        return ComputeConversationTokenHash(token, ModuleId);
    }

    private string ComputeConversationTokenHash(string token, int moduleId)
    {
        if (String.IsNullOrWhiteSpace(token)) return String.Empty;
        var source = "JacarandaQAConversation|" + PortalId + "|" + moduleId + "|" + token;
        using (var sha = SHA256.Create()) return BytesToHex(sha.ComputeHash(Encoding.UTF8.GetBytes(source)));
    }

    private void SetConversationCookie(int questionId, string token)
    {
        if (Response == null || String.IsNullOrWhiteSpace(token)) return;
        var cookie = new HttpCookie(ConversationCookiePrefix + PortalId + "_" + questionId, token);
        cookie.HttpOnly = true;
        cookie.Secure = Request != null && Request.IsSecureConnection;
        cookie.Expires = DateTime.UtcNow.AddDays(180);
        cookie.Path = "/";
        try { cookie.SameSite = SameSiteMode.Lax; } catch { }
        Response.Cookies.Set(cookie);
    }

    private bool ValidateConversationCookie(QuestionRow question)
    {
        if (question == null) return false;
        return ValidateConversationCookie(question.QuestionId, ModuleId, question.GuestConversationTokenHash);
    }

    private bool ValidateConversationCookie(int questionId, int moduleId, string expectedHash)
    {
        if (Request == null || questionId <= 0 || moduleId <= 0 || String.IsNullOrWhiteSpace(expectedHash)) return false;
        var cookie = Request.Cookies[ConversationCookiePrefix + PortalId + "_" + questionId];
        if (cookie == null || String.IsNullOrWhiteSpace(cookie.Value)) return false;
        return SecureEquals(expectedHash, ComputeConversationTokenHash(cookie.Value, moduleId));
    }

    private bool TryProtectGuestEmail(string email, out string protectedEmail)
    {
        protectedEmail = String.Empty;
        try
        {
            var protectedBytes = MachineKey.Protect(Encoding.UTF8.GetBytes(email.Trim()), "JacarandaQA", "GuestEmail", PortalId.ToString(), ModuleId.ToString());
            if (protectedBytes == null || protectedBytes.Length == 0) return false;
            protectedEmail = Convert.ToBase64String(protectedBytes);
            return protectedEmail.Length <= 2048;
        }
        catch (Exception ex) { Exceptions.LogException(ex); return false; }
    }

    private bool TryUnprotectGuestEmail(string protectedEmail, out string email)
    {
        email = String.Empty;
        if (String.IsNullOrWhiteSpace(protectedEmail) || protectedEmail.Length > 2048) return false;
        try
        {
            var protectedBytes = Convert.FromBase64String(protectedEmail);
            var clearBytes = MachineKey.Unprotect(protectedBytes, "JacarandaQA", "GuestEmail", PortalId.ToString(), ModuleId.ToString());
            if (clearBytes == null || clearBytes.Length == 0) return false;
            var candidate = Encoding.UTF8.GetString(clearBytes).Trim();
            if (!IsValidEmailAddress(candidate)) return false;
            email = candidate;
            return true;
        }
        catch (Exception ex) { Exceptions.LogException(ex); return false; }
    }

    private string GetOrCreateGuestBrowserToken()
    {
        var token = String.Empty;
        if (Request != null)
        {
            var cookie = Request.Cookies[GuestBrowserCookiePrefix + PortalId];
            if (cookie != null) token = (cookie.Value ?? String.Empty).Trim();
        }
        if ((token.Length < 20 || token.Length > 128) && Session != null)
            token = Convert.ToString(Session[GuestBrowserSessionKey]);
        if (token.Length < 20 || token.Length > 128)
            token = GenerateSecurityToken();

        if (Session != null) Session[GuestBrowserSessionKey] = token;
        if (Response != null)
        {
            var cookie = new HttpCookie(GuestBrowserCookiePrefix + PortalId, token);
            cookie.HttpOnly = true;
            cookie.Secure = Request != null && Request.IsSecureConnection;
            cookie.Expires = DateTime.UtcNow.AddDays(180);
            cookie.Path = "/";
            try { cookie.SameSite = SameSiteMode.Lax; } catch { }
            Response.Cookies.Set(cookie);
        }
        return token;
    }

    private string ComputeGuestRateLimitKey()
    {
        var browserToken = GetOrCreateGuestBrowserToken();
        if (String.IsNullOrWhiteSpace(browserToken)) return String.Empty;
        var source = "JacarandaQAGuestRateV2|" + PortalId + "|" + browserToken;
        using (var sha = SHA256.Create()) return BytesToHex(sha.ComputeHash(Encoding.UTF8.GetBytes(source)));
    }

    private static string BytesToHex(byte[] bytes)
    {
        var output = new StringBuilder(bytes.Length * 2);
        foreach (var b in bytes) output.Append(b.ToString("x2"));
        return output.ToString();
    }

    private void SendAdministratorSubmissionNotification(int questionId, string title, string displayName, string text, bool isGuest, string guestEmail, bool approved, bool isResponse, bool languageFlagged)
    {
        if (!_settings.EnableNotifications) return;
        var recipients = GetNotificationRecipients();
        if (recipients.Count == 0) return;
        var fromAddress = GetNotificationFromAddress(recipients.Count > 0 ? recipients[0] : String.Empty);
        if (!IsValidEmailAddress(fromAddress)) return;

        var action = isResponse
            ? (approved ? "New follow-up question" : "Follow-up question awaiting approval")
            : (approved ? "New theological question" : "Question awaiting approval");
        var subject = CleanEmailHeader(action + " — " + title);
        var body = "Jacaranda Q&A\r\n\r\nQuestion ID: " + questionId
            + "\r\nPage: " + GetPageTitle()
            + "\r\nAuthor: " + displayName
            + "\r\nSubmission: " + (isResponse ? "Follow-up question" : "Question")
            + "\r\nModeration: " + (approved ? "Approved" : "Awaiting approval")
            + "\r\nLanguage filter: " + (languageFlagged ? "Matched" : "No match")
            + (isGuest && !String.IsNullOrWhiteSpace(guestEmail) ? "\r\nGuest email (private): " + guestEmail : String.Empty)
            + "\r\nPage URL: " + BuildQuestionUrl(questionId)
            + (_settings.IncludeSubmissionTextInNotifications ? "\r\n\r\n" + text : String.Empty);
        foreach (var recipient in recipients)
        {
            SendPlainTextMail(fromAddress, recipient, subject, body);
        }
    }

    private void SendQuestionerModerationAcknowledgement(QuestionRow question)
    {
        if (!_settings.EnableNotifications || question == null || question.QuestionId <= 0) return;

        string recipient;
        if (!TryGetQuestionerEmail(question, out recipient)) return;

        var fromAddress = GetNotificationFromAddress(recipient);
        if (!IsValidEmailAddress(fromAddress)) return;

        var siteTitle = String.IsNullOrWhiteSpace(QaSiteTitle) ? "This site" : QaSiteTitle.Trim();
        var qaName = siteTitle + " Q&A";
        var subject = CleanEmailHeader("Your " + qaName + " question is awaiting moderation — " + question.QuestionTitle);
        var greetingName = String.IsNullOrWhiteSpace(question.DisplayName) ? "there" : question.DisplayName.Trim();

        var body = "Hello " + greetingName + ",\r\n\r\n"
            + "Thank you. Your question has been received by " + qaName + " and is awaiting moderation."
            + "\r\n\r\nQuestion: " + question.QuestionTitle
            + "\r\n\r\nYou do not need to submit the question again. We will email you when your question has been answered."
            + "\r\n\r\n" + qaName;

        SendPlainTextMail(fromAddress, recipient, subject, body);
    }

    private void SendQuestionerAnswerNotification(QuestionRow question, string answerText)
    {
        if (!_settings.EnableNotifications || question == null) return;

        string recipient;
        if (!TryGetQuestionerEmail(question, out recipient)) return;

        var fromAddress = GetNotificationFromAddress(recipient);
        if (!IsValidEmailAddress(fromAddress)) return;

        var siteTitle = String.IsNullOrWhiteSpace(QaSiteTitle) ? "This site" : QaSiteTitle.Trim();
        var qaName = siteTitle + " Q&A";
        var ministryAnswerCount = CountApprovedMinistryAnswers(question.QuestionId);
        var isFollowUpAnswer = ministryAnswerCount > 1;
        var subjectPrefix = isFollowUpAnswer
            ? "Your " + qaName + " follow-up has been answered"
            : "Your " + qaName + " question has been answered";
        var subject = CleanEmailHeader(subjectPrefix + " — " + question.QuestionTitle);

        var greetingName = String.IsNullOrWhiteSpace(question.DisplayName) ? "there" : question.DisplayName.Trim();
        var body = "Hello " + greetingName + ",\r\n\r\n"
            + (isFollowUpAnswer
                ? "A follow-up in your " + qaName + " conversation has been answered."
                : "Your " + qaName + " question has been answered.")
            + "\r\n\r\nQuestion: " + question.QuestionTitle
            + "\r\n\r\nAnswer:\r\n" + (answerText ?? String.Empty).Trim()
            + "\r\n\r\nView the conversation:\r\n" + BuildQuestionUrl(question.QuestionId)
            + "\r\n\r\n" + qaName;

        SendPlainTextMail(fromAddress, recipient, subject, body);
    }

    private bool TryGetQuestionerEmail(QuestionRow question, out string email)
    {
        email = String.Empty;
        if (question == null) return false;

        if (question.UserId.HasValue && question.UserId.Value > 0)
        {
            try
            {
                var user = UserController.GetUserById(PortalId, question.UserId.Value);
                if (user == null || !IsValidEmailAddress(user.Email)) return false;
                email = user.Email.Trim();
                return true;
            }
            catch (Exception ex)
            {
                Exceptions.LogException(ex);
                return false;
            }
        }

        return TryUnprotectGuestEmail(question.GuestEmailEncrypted, out email);
    }

    private int CountApprovedMinistryAnswers(int questionId)
    {
        if (questionId <= 0) return 0;
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT COUNT(1)
FROM " + ResponsesTable + @"
WHERE QuestionId = @QuestionId
  AND PortalId = @PortalId
  AND TabId = @TabId
  AND ModuleId = @ModuleId
  AND ResponseType = 1
  AND IsApproved = 1
  AND IsDeleted = 0;";
            command.Parameters.Add("@QuestionId", SqlDbType.Int).Value = questionId;
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@TabId", SqlDbType.Int).Value = TabId;
            command.Parameters.Add("@ModuleId", SqlDbType.Int).Value = ModuleId;
            connection.Open();
            return Convert.ToInt32(command.ExecuteScalar());
        }
    }

    private string BuildQuestionUrl(int questionId)
    {
        try
        {
            return DotNetNuke.Common.Globals.NavigateURL(
                TabId,
                String.Empty,
                AnswerModuleQueryKey + "=" + ModuleId,
                AnswerQuestionQueryKey + "=" + questionId)
                + "#jqa-question-" + questionId;
        }
        catch
        {
            return DotNetNuke.Common.Globals.NavigateURL(TabId) + "#jqa-question-" + questionId;
        }
    }

    private string GetNotificationFromAddress(string fallback)
    {
        var fromAddress = PortalSettings == null ? String.Empty : (PortalSettings.Email ?? String.Empty).Trim();
        if (!IsValidEmailAddress(fromAddress)) fromAddress = (fallback ?? String.Empty).Trim();
        return IsValidEmailAddress(fromAddress) ? fromAddress : String.Empty;
    }

    private void SendPlainTextMail(string fromAddress, string recipient, string subject, string body)
    {
        if (!IsValidEmailAddress(fromAddress) || !IsValidEmailAddress(recipient)) return;
        try
        {
            Mail.SendMail(fromAddress, recipient, String.Empty, CleanEmailHeader(subject), body ?? String.Empty,
                String.Empty, "text", String.Empty, String.Empty, String.Empty, String.Empty);
        }
        catch (Exception ex) { Exceptions.LogException(ex); }
    }

    private List<string> GetNotificationRecipients()
    {
        var result = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var raw = _settings.NotificationEmailAddresses;
        if (String.IsNullOrWhiteSpace(raw) && PortalSettings != null) raw = PortalSettings.Email;
        foreach (var part in (raw ?? String.Empty).Split(new[] {',',';','\r','\n'}, StringSplitOptions.RemoveEmptyEntries))
        {
            var email = part.Trim();
            if (IsValidEmailAddress(email) && seen.Add(email)) result.Add(email);
        }
        return result;
    }

    private bool IsValidEmailAddress(string email)
    {
        if (String.IsNullOrWhiteSpace(email) || email.Length > MaximumGuestEmailLength || email.IndexOfAny(new[] {'\r','\n'}) >= 0) return false;
        try
        {
            var address = new MailAddress(email.Trim());
            return String.Equals(address.Address, email.Trim(), StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    private string GetPageTitle()
    {
        if (PortalSettings != null && PortalSettings.ActiveTab != null && !String.IsNullOrWhiteSpace(PortalSettings.ActiveTab.TabName)) return PortalSettings.ActiveTab.TabName;
        return "DNN page";
    }

    private static string CleanEmailHeader(string value)
    {
        value = (value ?? String.Empty).Replace("\r", " ").Replace("\n", " ").Trim();
        return value.Length > 150 ? value.Substring(0, 150) : value;
    }

    private string GetCurrentUserDisplayName()
    {
        if (UserInfo == null) return String.Empty;
        var display = (UserInfo.DisplayName ?? String.Empty).Trim();
        if (String.IsNullOrWhiteSpace(display)) display = (UserInfo.Username ?? String.Empty).Trim();
        return Truncate(display, MaximumDisplayNameLength);
    }

    private PortalQaSettings ReadPortalSettings()
    {
        var result = PortalQaSettings.Defaults();
        try
        {
            using (var connection = new SqlConnection(ConnectionString))
            using (var command = connection.CreateCommand())
            {
                command.CommandText = @"
SELECT PostingEnabled, GuestPostingEnabled, RequireRegisteredModeration, EnableLanguageFilter, BlockedLanguageTerms,
       MaximumQuestionLength, MaximumResponseLength, MaximumFollowUpQuestions, EnableRateLimiting, RateLimitSeconds, RateLimitMaxPosts,
       RateLimitWindowMinutes, EnableCaptcha, EnableNotifications, NotificationEmailAddresses,
       IncludeSubmissionTextInNotifications
FROM " + PortalSettingsTable + @" WHERE PortalId = @PortalId;";
                command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                connection.Open();
                using (var reader = command.ExecuteReader())
                {
                    if (reader.Read())
                    {
                        result.PostingEnabled = ReadBool(reader, "PostingEnabled", true);
                        result.GuestPostingEnabled = ReadBool(reader, "GuestPostingEnabled", false);
                        result.RequireRegisteredModeration = ReadBool(reader, "RequireRegisteredModeration", true);
                        result.EnableLanguageFilter = ReadBool(reader, "EnableLanguageFilter", false);
                        result.BlockedLanguageTerms = ReadString(reader, "BlockedLanguageTerms", String.Empty);
                        result.MaximumQuestionLength = Clamp(ReadInt(reader, "MaximumQuestionLength", 4000), 250, 10000);
                        result.MaximumResponseLength = Clamp(ReadInt(reader, "MaximumResponseLength", 4000), 250, 10000);
                        result.MaximumFollowUpQuestions = Clamp(ReadInt(reader, "MaximumFollowUpQuestions", 4), 0, 20);
                        result.EnableRateLimiting = ReadBool(reader, "EnableRateLimiting", true);
                        result.RateLimitSeconds = Clamp(ReadInt(reader, "RateLimitSeconds", 60), 0, 3600);
                        result.RateLimitMaxPosts = Clamp(ReadInt(reader, "RateLimitMaxPosts", 5), 1, 100);
                        result.RateLimitWindowMinutes = Clamp(ReadInt(reader, "RateLimitWindowMinutes", 15), 1, 1440);
                        result.EnableCaptcha = ReadBool(reader, "EnableCaptcha", false);
                        result.EnableNotifications = ReadBool(reader, "EnableNotifications", false);
                        result.NotificationEmailAddresses = ReadString(reader, "NotificationEmailAddresses", String.Empty);
                        result.IncludeSubmissionTextInNotifications = ReadBool(reader, "IncludeSubmissionTextInNotifications", true);
                    }
                }
            }
        }
        catch (Exception ex) { Exceptions.LogException(ex); }
        return result;
    }

    private void ShowMessage(string message, bool success)
    {
        pnlMessage.Visible = true;
        pnlMessage.CssClass = success ? "jqa-message jqa-message-success" : "jqa-message jqa-message-error";
        pnlMessage.Attributes["role"] = success ? "status" : "alert";
        pnlMessage.Attributes["aria-live"] = success ? "polite" : "assertive";
        litMessage.Text = success
            ? "<strong>Process complete.</strong> " + HttpUtility.HtmlEncode(message)
            : HttpUtility.HtmlEncode(message);
    }

    private string GetDnnTableName(string tableName)
    {
        var provider = DataProvider.Instance();
        var owner = CleanSqlIdentifierPart(provider.DatabaseOwner, "dbo");
        var qualifier = CleanSqlIdentifierPart(provider.ObjectQualifier, String.Empty);
        return "[" + owner + "].[" + qualifier + tableName + "]";
    }

    private static string CleanSqlIdentifierPart(string value, string defaultValue)
    {
        value = (value ?? String.Empty).Trim();
        if (value.EndsWith(".", StringComparison.Ordinal)) value = value.Substring(0, value.Length - 1);
        value = value.Replace("[", String.Empty).Replace("]", String.Empty).Trim();
        if (String.IsNullOrEmpty(value)) return defaultValue ?? String.Empty;
        foreach (var c in value)
            if (!(Char.IsLetterOrDigit(c) || c == '_')) return defaultValue ?? String.Empty;
        return value;
    }

    private static string NormalizeSingleLineText(string value)
    {
        value = (value ?? String.Empty).Trim();
        var output = new StringBuilder(value.Length);
        var white = false;
        foreach (var c in value)
        {
            if (Char.IsControl(c) || Char.IsWhiteSpace(c))
            {
                if (!white) { output.Append(' '); white = true; }
            }
            else { output.Append(c); white = false; }
        }
        return output.ToString().Trim();
    }

    private static string Truncate(string value, int max) { value = value ?? String.Empty; return value.Length <= max ? value : value.Substring(0, max); }
    private static int Clamp(int value, int min, int max) { return value < min ? min : (value > max ? max : value); }
    private static bool ReadBool(IDataRecord r, string name, bool d) { try { return r[name] == DBNull.Value ? d : Convert.ToBoolean(r[name]); } catch { return d; } }
    private static int ReadInt(IDataRecord r, string name, int d) { try { return r[name] == DBNull.Value ? d : Convert.ToInt32(r[name]); } catch { return d; } }
    private static string ReadString(IDataRecord r, string name, string d) { try { return r[name] == DBNull.Value ? d : Convert.ToString(r[name]); } catch { return d; } }

    private sealed class PortalQaSettings
    {
        public bool PostingEnabled, GuestPostingEnabled, RequireRegisteredModeration, EnableLanguageFilter, EnableRateLimiting, EnableCaptcha, EnableNotifications, IncludeSubmissionTextInNotifications;
        public string BlockedLanguageTerms, NotificationEmailAddresses;
        public int MaximumQuestionLength, MaximumResponseLength, MaximumFollowUpQuestions, RateLimitSeconds, RateLimitMaxPosts, RateLimitWindowMinutes;
        public static PortalQaSettings Defaults()
        {
            return new PortalQaSettings {
                PostingEnabled = true, GuestPostingEnabled = false, RequireRegisteredModeration = true,
                EnableLanguageFilter = false, BlockedLanguageTerms = String.Empty,
                MaximumQuestionLength = 4000, MaximumResponseLength = 4000, MaximumFollowUpQuestions = 4,
                EnableRateLimiting = true, RateLimitSeconds = 60, RateLimitMaxPosts = 5, RateLimitWindowMinutes = 15,
                EnableCaptcha = false, EnableNotifications = false, NotificationEmailAddresses = String.Empty,
                IncludeSubmissionTextInNotifications = true
            };
        }
    }

    protected sealed class QuestionRow
    {
        public int QuestionId { get; set; }
        public int? UserId { get; set; }
        public string DisplayName { get; set; }
        public string GuestEmailEncrypted { get; set; }
        public string GuestConversationTokenHash { get; set; }
        public string QuestionTitle { get; set; }
        public string QuestionText { get; set; }
        public int QuestionStatus { get; set; }
        public bool IsLanguageFlagged { get; set; }
        public DateTime CreatedOnDate { get; set; }
        public List<ResponseRow> Responses { get; set; }
    }

    protected sealed class ResponseRow
    {
        public int ResponseId { get; set; }
        public int ResponseType { get; set; }
        public int? UserId { get; set; }
        public string DisplayName { get; set; }
        public string ResponseText { get; set; }
        public bool IsLanguageFlagged { get; set; }
        public bool IsRichText { get; set; }
        public DateTime CreatedOnDate { get; set; }
    }

    private sealed class AnswerDraftRow
    {
        public string DraftHtml { get; set; }
        public DateTime CreatedOnDate { get; set; }
        public DateTime ModifiedOnDate { get; set; }
    }
</script>

<div class="jacaranda-qa">
    <asp:Panel ID="pnlAdminToolbar" runat="server" Visible="false" CssClass="jqa-admin-toolbar">
        <div class="jqa-admin-toolbar-summary">
            <strong>Q&amp;A Administration</strong>
            <span><asp:Literal ID="litAdminPendingCount" runat="server" /> pending moderation</span>
            <span><asp:Literal ID="litAdminAwaitingCount" runat="server" /> awaiting answer</span>
        </div>
        <asp:HyperLink ID="lnkAdministration" runat="server" CssClass="jqa-admin-toolbar-link" Text="Open Q&amp;A Administration" />
    </asp:Panel>

    <div id="<%= PostRedirectMessageAnchorId %>" class="jqa-message-anchor">
        <asp:Panel ID="pnlMessage" runat="server" Visible="false" CssClass="jqa-message" role="status" aria-live="polite">
            <asp:Literal ID="litMessage" runat="server" />
        </asp:Panel>
    </div>

    <asp:HiddenField ID="hdnSecurityToken" runat="server" />

    <asp:Panel ID="pnlAskSection" runat="server" CssClass="jqa-ask-section">
        <asp:Panel ID="pnlAskLauncher" runat="server" CssClass="jqa-ask-launcher">
            <asp:LinkButton ID="btnToggleAskQuestion" runat="server" Text="Ask a Question"
                CssClass="jqa-ask-button" CausesValidation="false"
                OnClick="btnToggleAskQuestion_Click" />
            <p class="jqa-guidance"><strong>Please ask one question at a time.</strong> <%= HttpUtility.HtmlEncode(QaSiteTitle) %> Q&amp;A is intended as a moderated question-and-answer ministry rather than an open discussion forum. <%= HttpUtility.HtmlEncode(FollowUpGuidanceText) %></p>
        </asp:Panel>

        <asp:Panel ID="pnlAskForm" runat="server" Visible="false" CssClass="jqa-ask-panel"
            role="region" aria-labelledby="jqaAskHeading">
            <h2 id="jqaAskHeading">Ask a Question</h2>
            <p class="jqa-intro">Questions are moderated so that the conversation can remain gracious, thoughtful and Christ-like. Please keep each submission to one question rather than opening a general discussion.</p>

            <asp:Panel ID="pnlPostingClosed" runat="server" Visible="false" CssClass="jqa-message jqa-message-info">
                New questions are temporarily closed.
            </asp:Panel>
            <asp:Panel ID="pnlLoginRequired" runat="server" Visible="false" CssClass="jqa-message jqa-message-info">
                Please sign in to ask a question.
            </asp:Panel>

            <asp:Panel ID="pnlAskQuestion" runat="server">
                <asp:Panel ID="pnlRegisteredIdentity" runat="server" Visible="false" CssClass="jqa-identity">
                    Asking as <strong><asp:Literal ID="litQuestionIdentity" runat="server" /></strong>
                </asp:Panel>
                <asp:Panel ID="pnlGuestIdentity" runat="server" Visible="false">
                    <div class="jqa-field">
                        <asp:Label ID="lblGuestName" runat="server" AssociatedControlID="txtGuestName" Text="Name shown publicly" />
                        <asp:TextBox ID="txtGuestName" runat="server" CssClass="jqa-input" MaxLength="100" />
                    </div>
                    <div class="jqa-field">
                        <asp:Label ID="lblGuestEmail" runat="server" AssociatedControlID="txtGuestEmail" Text="Email (private)" />
                        <asp:TextBox ID="txtGuestEmail" runat="server" CssClass="jqa-input" MaxLength="254" TextMode="Email" />
                        <span class="jqa-help">Your email address is used only for this Q&amp;A conversation and is never displayed publicly.</span>
                    </div>
                </asp:Panel>
                <div class="jqa-field">
                    <asp:Label ID="lblQuestionTitle" runat="server" AssociatedControlID="txtQuestionTitle" Text="Question title" />
                    <asp:TextBox ID="txtQuestionTitle" runat="server" CssClass="jqa-input" MaxLength="250" />
                </div>
                <div class="jqa-field">
                    <asp:Label ID="lblQuestion" runat="server" AssociatedControlID="txtQuestion" Text="Your question" />
                    <asp:TextBox ID="txtQuestion" runat="server" CssClass="jqa-textarea" TextMode="MultiLine" Rows="7" />
                </div>
                <div class="jqa-honeypot" aria-hidden="true">
                    <asp:Label ID="lblWebsite" runat="server" AssociatedControlID="txtWebsite" Text="Website" />
                    <asp:TextBox ID="txtWebsite" runat="server" TabIndex="-1" autocomplete="off" />
                </div>
                <asp:Panel ID="pnlQuestionCaptcha" runat="server" Visible="false" CssClass="jqa-field jqa-captcha">
                    <asp:Label ID="lblQuestionCaptcha" runat="server" AssociatedControlID="txtQuestionCaptcha" Text="Anti-spam question: " />
                    <asp:Literal ID="litQuestionCaptcha" runat="server" />
                    <asp:TextBox ID="txtQuestionCaptcha" runat="server" CssClass="jqa-captcha-input" MaxLength="3" />
                </asp:Panel>
                <asp:Button ID="btnSubmitQuestion" runat="server" Text="Submit Question" CssClass="jqa-submit" OnClick="btnSubmitQuestion_Click" />
            </asp:Panel>
        </asp:Panel>
    </asp:Panel>


    <asp:Panel ID="pnlGuestCorrection" runat="server" Visible="false" CssClass="jqa-guest-correction"
        role="region" aria-labelledby="jqaGuestCorrectionHeading">
        <h2 id="jqaGuestCorrectionHeading">Review your question</h2>
        <p>Your question is awaiting moderation. You have <strong>one opportunity</strong>, available for up to 5 minutes after submission, to correct the <strong>title and question text</strong>. Once you save the correction, the correction window closes. Your public name and private email cannot be changed.</p>
        <p class="jqa-correction-time"><strong>Time remaining:</strong> <span id="<%= GuestCorrectionCountdownId %>">5:00</span></p>
        <asp:HiddenField ID="hdnGuestEditQuestionId" runat="server" />
        <div class="jqa-field">
            <asp:Label ID="lblGuestEditTitle" runat="server" AssociatedControlID="txtGuestEditTitle" Text="Question title" />
            <asp:TextBox ID="txtGuestEditTitle" runat="server" CssClass="jqa-input" MaxLength="250" />
        </div>
        <div class="jqa-field">
            <asp:Label ID="lblGuestEditQuestion" runat="server" AssociatedControlID="txtGuestEditQuestion" Text="Your question" />
            <asp:TextBox ID="txtGuestEditQuestion" runat="server" CssClass="jqa-textarea" TextMode="MultiLine" Rows="7" />
        </div>
        <div class="jqa-actions">
            <asp:Button ID="btnSaveGuestCorrection" runat="server" Text="Save Corrections"
                CssClass="jqa-submit" OnClick="btnSaveGuestCorrection_Click" />
        </div>
    </asp:Panel>

    <section class="jqa-conversations" aria-labelledby="jqaQuestionsHeading">
        <h2 id="jqaQuestionsHeading"><asp:Literal ID="litQuestionsHeading" runat="server" Text="Questions &amp; Answers" /></h2>
        <asp:Panel ID="pnlNoQuestions" runat="server" Visible="false" CssClass="jqa-empty">There are no published questions yet.</asp:Panel>
        <asp:Repeater ID="rptQuestions" runat="server" OnItemCommand="rptQuestions_ItemCommand">
            <ItemTemplate>
                <article class='<%# QuestionCss(Container.DataItem) %>' id='jqa-question-<%# Eval("QuestionId") %>'>
                    <header class="jqa-question-header">
                        <h3>
                            <button type="button" class="jqa-question-title-button"
                                data-jqa-question-toggle
                                aria-expanded='<%# QuestionExpandedValue(Container.DataItem) %>'
                                aria-controls='jqa-question-body-<%# Eval("QuestionId") %>'>
                                <%# Encode(Eval("QuestionTitle")) %>
                            </button>
                        </h3>
                        <span class='<%# StatusCss(Eval("QuestionStatus")) %>'><%# StatusText(Eval("QuestionStatus")) %></span>
                    </header>
                    <div class="jqa-question-body" id='jqa-question-body-<%# Eval("QuestionId") %>'>
                        <div class="jqa-meta">Asked by <strong><%# Encode(Eval("DisplayName")) %></strong> · <%# FormatDate(Eval("CreatedOnDate")) %></div>
                        <div class="jqa-question-text"><%# Encode(Eval("QuestionText")) %></div>

                    <asp:Repeater ID="rptResponses" runat="server" DataSource='<%# Eval("Responses") %>'>
                        <ItemTemplate>
                            <div class='<%# ResponseCss(Eval("ResponseType")) %>'>
                                <div class="jqa-response-heading">
                                    <strong><%# ResponseRole(Eval("ResponseType")) %></strong>
                                    <span><%# Encode(Eval("DisplayName")) %> · <%# FormatDate(Eval("CreatedOnDate")) %></span>
                                </div>
                                <div class='jqa-response-text<%# ResponseTextCss(Container.DataItem) %>'><%# RenderResponseText(Container.DataItem) %></div>
                            </div>
                        </ItemTemplate>
                    </asp:Repeater>

                    <div class="jqa-question-actions">
                        <asp:LinkButton ID="btnAnswer" runat="server" CommandName="Answer" CommandArgument='<%# Eval("QuestionId") %>' Text="Answer" CssClass="jqa-secondary-button" CausesValidation="false" Visible='<%# CanShowAnswerButton(Container.DataItem) %>' />
                        <asp:LinkButton ID="btnFollowUp" runat="server" CommandName="FollowUp" CommandArgument='<%# Eval("QuestionId") %>' Text="Ask a follow-up" CssClass="jqa-secondary-button" CausesValidation="false" Visible='<%# CanShowFollowUpButton(Container.DataItem) %>' />
                    </div>
                    <asp:Panel ID="pnlFollowUpLimit" runat="server" CssClass="jqa-message jqa-message-info" Visible='<%# ShouldShowFollowUpLimitMessage(Container.DataItem) %>'>
                        <%# HttpUtility.HtmlEncode(GetFollowUpLimitMessage()) %>
                    </asp:Panel>
                    </div>
                </article>
            </ItemTemplate>
        </asp:Repeater>

    <asp:Panel ID="pnlResponseForm" runat="server" Visible="false" CssClass="jqa-response-form">
        <h3><asp:Literal ID="litResponseHeading" runat="server" /></h3>
        <p class="jqa-context-title"><asp:Literal ID="litResponseQuestionTitle" runat="server" /></p>
        <asp:HiddenField ID="hdnResponseQuestionId" runat="server" />
        <asp:HiddenField ID="hdnResponseMode" runat="server" />
<asp:Panel ID="pnlPlainResponseEditor" runat="server">
            <div class="jqa-field">
                <asp:Label ID="lblResponse" runat="server" AssociatedControlID="txtResponse" Text="Response" />
                <asp:TextBox ID="txtResponse" runat="server" CssClass="jqa-textarea" TextMode="MultiLine" Rows="7" />
            </div>
        </asp:Panel>
        <asp:Panel ID="pnlRichAnswerEditor" runat="server" Visible="false" CssClass="jqa-rich-answer-editor">
            <div class="jqa-field">
                <strong>Answer</strong>
                <p class="jqa-editor-help">Use the site editor to prepare the ministry answer. Drafts are private until you choose Publish Answer.</p>
                <dnn:textEditor ID="txtAnswerEditor" runat="server"
                    Height="360" Width="100%" ChooseMode="false" HtmlEncode="false" />
                <div class="jqa-editor-mode-selector">
                    <asp:Label ID="lblAnswerEditorMode" runat="server" AssociatedControlID="ddlAnswerEditorMode" Text="Editor mode" CssClass="jqa-editor-mode-label" />
                    <asp:DropDownList ID="ddlAnswerEditorMode" runat="server"
                        AutoPostBack="true"
                        CssClass="jqa-editor-mode-select"
                        OnSelectedIndexChanged="ddlAnswerEditorMode_SelectedIndexChanged" />
                </div>
                <p class="jqa-draft-status"><asp:Literal ID="litDraftStatus" runat="server" /></p>
            </div>
        </asp:Panel>
        <div class="jqa-honeypot" aria-hidden="true">
            <asp:Label ID="lblResponseWebsite" runat="server" AssociatedControlID="txtResponseWebsite" Text="Website" />
            <asp:TextBox ID="txtResponseWebsite" runat="server" TabIndex="-1" autocomplete="off" />
        </div>
        <asp:Panel ID="pnlResponseCaptcha" runat="server" Visible="false" CssClass="jqa-field jqa-captcha">
            <asp:Label ID="lblResponseCaptcha" runat="server" AssociatedControlID="txtResponseCaptcha" Text="Anti-spam question: " />
            <asp:Literal ID="litResponseCaptcha" runat="server" />
            <asp:TextBox ID="txtResponseCaptcha" runat="server" CssClass="jqa-captcha-input" MaxLength="3" />
        </asp:Panel>
        <div class="jqa-actions">
            <asp:Button ID="btnSaveDraft" runat="server" Text="Save Draft" CssClass="jqa-secondary-button" Visible="false" OnClick="btnSaveDraft_Click" />
            <asp:Button ID="btnSubmitResponse" runat="server" Text="Submit Response" CssClass="jqa-submit" OnClick="btnSubmitResponse_Click" />
            <asp:Button ID="btnCancelResponse" runat="server" Text="Cancel" CssClass="jqa-secondary-button" CausesValidation="false" OnClick="btnCancelResponse_Click" />
        </div>
    </asp:Panel>

    </section>

<script type="text/javascript">
(function () {
    function findArticle(element) {
        while (element && element !== document) {
            if (element.classList && element.classList.contains('jqa-question')) return element;
            element = element.parentNode;
        }
        return null;
    }

    function setExpanded(article, expanded) {
        if (!article) return;
        if (expanded) article.classList.add('jqa-question-expanded');
        else article.classList.remove('jqa-question-expanded');
        var toggle = article.querySelector('[data-jqa-question-toggle]');
        if (toggle) toggle.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    }

    function openOnly(article, shouldScroll) {
        if (!article) return;
        var root = article.parentNode;
        while (root && root !== document && !(root.classList && root.classList.contains('jqa-conversations'))) root = root.parentNode;
        var all = (root || document).querySelectorAll('.jqa-question');
        for (var i = 0; i < all.length; i++) setExpanded(all[i], all[i] === article);
        if (shouldScroll) {
            window.setTimeout(function () {
                try { article.scrollIntoView({ behavior: 'auto', block: 'start' }); }
                catch (e) { try { article.scrollIntoView(true); } catch (ignore) { } }
            }, 25);
        }
    }

    document.addEventListener('click', function (event) {
        var target = event.target;
        while (target && target !== document && !(target.getAttribute && target.getAttribute('data-jqa-question-toggle') !== null)) target = target.parentNode;
        if (!target || target === document) return;
        var article = findArticle(target);
        if (!article) return;
        var isOpen = article.classList.contains('jqa-question-expanded');
        if (isOpen) setExpanded(article, false);
        else openOnly(article, false);
    });

    function openHashQuestion() {
        var hash = window.location.hash || '';
        if (hash.indexOf('#jqa-question-') !== 0) return;
        var article = document.getElementById(hash.substring(1));
        if (article) openOnly(article, false);
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', openHashQuestion);
    else openHashQuestion();
    window.addEventListener('hashchange', openHashQuestion);
})();
</script>
</div>
