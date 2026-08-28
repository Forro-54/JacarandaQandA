<%@ Control Language="C#" AutoEventWireup="true" Inherits="DotNetNuke.Entities.Modules.PortalModuleBase" %>
<%@ Import Namespace="System" %>
<%@ Import Namespace="System.Collections.Generic" %>
<%@ Import Namespace="System.Data" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Security.Cryptography" %>
<%@ Import Namespace="System.Text" %>
<%@ Import Namespace="System.Web" %>
<%@ Import Namespace="System.Web.UI.WebControls" %>
<%@ Import Namespace="DotNetNuke.Common.Utilities" %>
<%@ Import Namespace="DotNetNuke.Data" %>
<%@ Import Namespace="DotNetNuke.Services.Exceptions" %>

<script runat="server">
    private const string SecurityTokenPrefix = "JacarandaQA_AdminSecurityToken_";
    private const int MaximumBlockedTermCount = 250;
    private const int MaximumBlockedTermLength = 100;
    private const string AnswerQuestionQueryKey = "jqaqid";
    private const string AnswerModuleQueryKey = "jqamid";
    private const string AnswerActionQueryKey = "jqaaction";
    private const int AdminPageSize = 20;
    private const string TabDashboard = "dashboard";
    private const string TabPending = "pending";
    private const string TabAwaiting = "awaiting";
    private const string TabAnswered = "answered";
    private const string TabClosed = "closed";
    private const string TabSettings = "settings";

    private string QuestionsTable { get { return GetDnnTableName("JacarandaQAQuestions"); } }
    private string ResponsesTable { get { return GetDnnTableName("JacarandaQAResponses"); } }
    private string PortalSettingsTable { get { return GetDnnTableName("JacarandaQAPortalSettings"); } }
    private string ConnectionString { get { return Config.GetConnectionString(); } }
    private string SecurityTokenSessionKey { get { return SecurityTokenPrefix + PortalId + "_" + UserId; } }

    private string QaSiteTitle
    {
        get
        {
            var title = PortalSettings == null ? String.Empty : (PortalSettings.PortalName ?? String.Empty).Trim();
            return String.IsNullOrWhiteSpace(title) ? "This site" : title;
        }
    }

    private string ActiveTab
    {
        get
        {
            var value = Convert.ToString(ViewState["JQAActiveAdminTab"]);
            return NormalizeTab(value);
        }
        set { ViewState["JQAActiveAdminTab"] = NormalizeTab(value); }
    }

    private int GetPageIndex(string key)
    {
        int value;
        return Int32.TryParse(Convert.ToString(ViewState["JQAPage_" + key]), out value) && value > 0 ? value : 0;
    }

    private void SetPageIndex(string key, int value)
    {
        ViewState["JQAPage_" + key] = Math.Max(0, value);
    }

    protected void Page_Load(object sender, EventArgs e)
    {
        if (!CanManagePortalQandA())
        {
            pnlAccessDenied.Visible = true;
            pnlAdministration.Visible = false;
            return;
        }

        pnlAccessDenied.Visible = false;
        pnlAdministration.Visible = true;

        try
        {
            if (!Page.IsPostBack)
            {
                EnsureSecurityToken();
                ActiveTab = TabDashboard;
                RefreshAdministration();
            }
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            ShowMessage("Q&A Administration could not be loaded. Please check the DNN Event Viewer.", false);
        }
    }

    private bool CanManagePortalQandA()
    {
        if (UserInfo == null) return false;
        if (UserInfo.IsSuperUser) return true;
        var role = PortalSettings == null ? String.Empty : (PortalSettings.AdministratorRoleName ?? String.Empty).Trim();
        return !String.IsNullOrWhiteSpace(role) && UserInfo.IsInRole(role);
    }

    protected void btnSave_Click(object sender, EventArgs e)
    {
        if (!CanManagePortalQandA() || !ValidateSecurityToken())
        {
            ShowMessage("The administration security token expired. Please refresh and try again.", false);
            return;
        }

        try
        {
            var blockedTerms = NormalizeBlockedTerms(txtBlockedLanguageTerms.Text);
            var maximumQuestionLength = ParseInt(txtMaximumQuestionLength.Text, 4000, 250, 10000);
            var maximumResponseLength = ParseInt(txtMaximumResponseLength.Text, 4000, 250, 10000);
            var rateSeconds = ParseInt(txtRateLimitSeconds.Text, 60, 0, 3600);
            var rateMaxPosts = ParseInt(txtRateLimitMaxPosts.Text, 5, 1, 100);
            var rateWindow = ParseInt(txtRateLimitWindowMinutes.Text, 15, 1, 1440);
            var notify = Truncate((txtNotificationEmailAddresses.Text ?? String.Empty).Trim(), 2000);

            using (var connection = new SqlConnection(ConnectionString))
            using (var command = connection.CreateCommand())
            {
                command.CommandText = @"
IF EXISTS (SELECT 1 FROM " + PortalSettingsTable + @" WHERE PortalId = @PortalId)
BEGIN
    UPDATE " + PortalSettingsTable + @"
       SET PostingEnabled = @PostingEnabled,
           GuestPostingEnabled = @GuestPostingEnabled,
           RequireRegisteredModeration = @RequireRegisteredModeration,
           EnableLanguageFilter = @EnableLanguageFilter,
           BlockedLanguageTerms = @BlockedLanguageTerms,
           MaximumQuestionLength = @MaximumQuestionLength,
           MaximumResponseLength = @MaximumResponseLength,
           EnableRateLimiting = @EnableRateLimiting,
           RateLimitSeconds = @RateLimitSeconds,
           RateLimitMaxPosts = @RateLimitMaxPosts,
           RateLimitWindowMinutes = @RateLimitWindowMinutes,
           EnableCaptcha = @EnableCaptcha,
           EnableNotifications = @EnableNotifications,
           NotificationEmailAddresses = @NotificationEmailAddresses,
           IncludeSubmissionTextInNotifications = @IncludeSubmissionText,
           ModifiedOnDate = GETUTCDATE(),
           ModifiedByUserId = @UserId
     WHERE PortalId = @PortalId;
END
ELSE
BEGIN
    INSERT INTO " + PortalSettingsTable + @"
    (PortalId, PostingEnabled, GuestPostingEnabled, RequireRegisteredModeration, EnableLanguageFilter,
     BlockedLanguageTerms, MaximumQuestionLength, MaximumResponseLength, EnableRateLimiting, RateLimitSeconds,
     RateLimitMaxPosts, RateLimitWindowMinutes, EnableCaptcha, EnableNotifications, NotificationEmailAddresses,
     IncludeSubmissionTextInNotifications, ModifiedOnDate, ModifiedByUserId)
    VALUES
    (@PortalId, @PostingEnabled, @GuestPostingEnabled, @RequireRegisteredModeration, @EnableLanguageFilter,
     @BlockedLanguageTerms, @MaximumQuestionLength, @MaximumResponseLength, @EnableRateLimiting, @RateLimitSeconds,
     @RateLimitMaxPosts, @RateLimitWindowMinutes, @EnableCaptcha, @EnableNotifications, @NotificationEmailAddresses,
     @IncludeSubmissionText, GETUTCDATE(), @UserId);
END";
                command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                command.Parameters.Add("@PostingEnabled", SqlDbType.Bit).Value = chkPostingEnabled.Checked;
                command.Parameters.Add("@GuestPostingEnabled", SqlDbType.Bit).Value = chkGuestPostingEnabled.Checked;
                command.Parameters.Add("@RequireRegisteredModeration", SqlDbType.Bit).Value = chkRequireRegisteredModeration.Checked;
                command.Parameters.Add("@EnableLanguageFilter", SqlDbType.Bit).Value = chkEnableLanguageFilter.Checked;
                command.Parameters.Add("@BlockedLanguageTerms", SqlDbType.NVarChar, -1).Value = String.IsNullOrWhiteSpace(blockedTerms) ? (object)DBNull.Value : blockedTerms;
                command.Parameters.Add("@MaximumQuestionLength", SqlDbType.Int).Value = maximumQuestionLength;
                command.Parameters.Add("@MaximumResponseLength", SqlDbType.Int).Value = maximumResponseLength;
                command.Parameters.Add("@EnableRateLimiting", SqlDbType.Bit).Value = chkEnableRateLimiting.Checked;
                command.Parameters.Add("@RateLimitSeconds", SqlDbType.Int).Value = rateSeconds;
                command.Parameters.Add("@RateLimitMaxPosts", SqlDbType.Int).Value = rateMaxPosts;
                command.Parameters.Add("@RateLimitWindowMinutes", SqlDbType.Int).Value = rateWindow;
                command.Parameters.Add("@EnableCaptcha", SqlDbType.Bit).Value = chkEnableCaptcha.Checked;
                command.Parameters.Add("@EnableNotifications", SqlDbType.Bit).Value = chkEnableNotifications.Checked;
                command.Parameters.Add("@NotificationEmailAddresses", SqlDbType.NVarChar, 2000).Value = String.IsNullOrWhiteSpace(notify) ? (object)DBNull.Value : notify;
                command.Parameters.Add("@IncludeSubmissionText", SqlDbType.Bit).Value = chkIncludeSubmissionText.Checked;
                command.Parameters.Add("@UserId", SqlDbType.Int).Value = UserInfo.UserID;
                connection.Open();
                command.ExecuteNonQuery();
            }

            EnsureSecurityToken(true);
            ActiveTab = TabSettings;
            LoadSettings();
            RefreshAdministration(false);
            ShowMessage("Q&A portal settings have been saved.", true);
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            ShowMessage("The Q&A settings could not be saved. Please check the DNN Event Viewer.", false);
        }
    }

    protected void rptPending_ItemCommand(object source, System.Web.UI.WebControls.RepeaterCommandEventArgs e)
    {
        if (!CanManagePortalQandA() || !ValidateSecurityToken())
        {
            ShowMessage("The administration security token expired. Please refresh and try again.", false);
            return;
        }

        var key = Convert.ToString(e.CommandArgument);
        if (String.IsNullOrWhiteSpace(key) || key.Length < 3 || key[1] != ':') return;
        int id;
        if (!Int32.TryParse(key.Substring(2), out id) || id <= 0) return;
        var type = Char.ToUpperInvariant(key[0]);

        try
        {
            if (String.Equals(e.CommandName, "Approve", StringComparison.OrdinalIgnoreCase))
            {
                if (type == 'Q') ApproveQuestion(id);
                else if (type == 'R') ApproveResponse(id);
                else return;
                ShowMessage("The pending submission has been approved.", true);
            }
            else if (String.Equals(e.CommandName, "Delete", StringComparison.OrdinalIgnoreCase))
            {
                if (type == 'Q') DeleteQuestion(id);
                else if (type == 'R') DeleteResponse(id);
                else return;
                ShowMessage("The pending submission has been rejected/deleted.", true);
            }
            EnsureSecurityToken(true);
            ActiveTab = TabPending;
            RefreshAdministration();
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            ShowMessage("The moderation action could not be completed.", false);
        }
    }

    protected void rptQuestions_ItemCommand(object source, RepeaterCommandEventArgs e)
    {
        if (!CanManagePortalQandA() || !ValidateSecurityToken())
        {
            ShowMessage("The administration security token expired. Please refresh and try again.", false);
            return;
        }
        int id;
        if (!Int32.TryParse(Convert.ToString(e.CommandArgument), out id) || id <= 0) return;
        try
        {
            var message = "The question status has been updated.";
            if (String.Equals(e.CommandName, "Close", StringComparison.OrdinalIgnoreCase))
            {
                SetQuestionStatus(id, 2);
            }
            else if (String.Equals(e.CommandName, "Reopen", StringComparison.OrdinalIgnoreCase))
            {
                SetQuestionStatus(id, 0);
            }
            else if (String.Equals(e.CommandName, "MarkAnswered", StringComparison.OrdinalIgnoreCase))
            {
                SetQuestionStatus(id, 1);
            }
            else if (String.Equals(e.CommandName, "DeleteFinished", StringComparison.OrdinalIgnoreCase))
            {
                if (!DeleteFinishedQuestion(id))
                {
                    ShowMessage("Only answered or closed questions can be deleted from the finished-question lists.", false);
                    return;
                }
                message = "The finished question and all of its responses have been deleted.";
            }
            else return;

            EnsureSecurityToken(true);
            RefreshAdministration();
            ShowMessage(message, true);
        }
        catch (Exception ex)
        {
            Exceptions.LogException(ex);
            ShowMessage("The question action could not be completed.", false);
        }
    }

    private void ApproveQuestion(int questionId)
    {
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
UPDATE " + QuestionsTable + @"
SET IsApproved = 1, GuestEditTokenHash = NULL, LastModifiedOnDate = GETUTCDATE(), LastModifiedByUserId = @UserId
WHERE QuestionId = @Id AND PortalId = @PortalId AND IsDeleted = 0 AND IsApproved = 0;";
            AddAdminScope(command, questionId);
            connection.Open(); command.ExecuteNonQuery();
        }
    }

    private void ApproveResponse(int responseId)
    {
        using (var connection = new SqlConnection(ConnectionString))
        {
            connection.Open();
            using (var transaction = connection.BeginTransaction())
            {
                int questionId = 0;
                int responseType = 0;
                using (var select = connection.CreateCommand())
                {
                    select.Transaction = transaction;
                    select.CommandText = @"
SELECT TOP 1 QuestionId, ResponseType FROM " + ResponsesTable + @"
WHERE ResponseId = @Id AND PortalId = @PortalId AND IsDeleted = 0 AND IsApproved = 0;";
                    select.Parameters.Add("@Id", SqlDbType.Int).Value = responseId;
                    select.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                    using (var reader = select.ExecuteReader())
                    {
                        if (reader.Read())
                        {
                            questionId = Convert.ToInt32(reader["QuestionId"]);
                            responseType = Convert.ToInt32(reader["ResponseType"]);
                        }
                    }
                }
                if (questionId <= 0) { transaction.Rollback(); return; }

                using (var update = connection.CreateCommand())
                {
                    update.Transaction = transaction;
                    update.CommandText = @"
UPDATE " + ResponsesTable + @"
SET IsApproved = 1, GuestEditTokenHash = NULL, LastModifiedOnDate = GETUTCDATE(), LastModifiedByUserId = @UserId
WHERE ResponseId = @Id AND PortalId = @PortalId AND IsDeleted = 0 AND IsApproved = 0;";
                    update.Parameters.Add("@Id", SqlDbType.Int).Value = responseId;
                    update.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                    update.Parameters.Add("@UserId", SqlDbType.Int).Value = UserInfo.UserID;
                    update.ExecuteNonQuery();
                }

                using (var updateQuestion = connection.CreateCommand())
                {
                    updateQuestion.Transaction = transaction;
                    updateQuestion.CommandText = @"
UPDATE " + QuestionsTable + @"
SET QuestionStatus = @Status, LastModifiedOnDate = GETUTCDATE(), LastModifiedByUserId = @UserId
WHERE QuestionId = @QuestionId AND PortalId = @PortalId AND IsDeleted = 0;";
                    updateQuestion.Parameters.Add("@Status", SqlDbType.TinyInt).Value = responseType == 1 ? 1 : 0;
                    updateQuestion.Parameters.Add("@QuestionId", SqlDbType.Int).Value = questionId;
                    updateQuestion.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                    updateQuestion.Parameters.Add("@UserId", SqlDbType.Int).Value = UserInfo.UserID;
                    updateQuestion.ExecuteNonQuery();
                }
                transaction.Commit();
            }
        }
    }

    private void DeleteQuestion(int questionId)
    {
        using (var connection = new SqlConnection(ConnectionString))
        {
            connection.Open();
            using (var transaction = connection.BeginTransaction())
            {
                using (var command = connection.CreateCommand())
                {
                    command.Transaction = transaction;
                    command.CommandText = @"
UPDATE " + QuestionsTable + @"
SET IsDeleted = 1, LastModifiedOnDate = GETUTCDATE(), LastModifiedByUserId = @UserId
WHERE QuestionId = @Id AND PortalId = @PortalId AND IsDeleted = 0;
UPDATE " + ResponsesTable + @"
SET IsDeleted = 1, LastModifiedOnDate = GETUTCDATE(), LastModifiedByUserId = @UserId
WHERE QuestionId = @Id AND PortalId = @PortalId AND IsDeleted = 0;";
                    command.Parameters.Add("@Id", SqlDbType.Int).Value = questionId;
                    command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                    command.Parameters.Add("@UserId", SqlDbType.Int).Value = UserInfo.UserID;
                    command.ExecuteNonQuery();
                }
                transaction.Commit();
            }
        }
    }

    private bool DeleteFinishedQuestion(int questionId)
    {
        using (var connection = new SqlConnection(ConnectionString))
        {
            connection.Open();
            using (var transaction = connection.BeginTransaction())
            {
                int affected;
                using (var question = connection.CreateCommand())
                {
                    question.Transaction = transaction;
                    question.CommandText = @"
UPDATE " + QuestionsTable + @"
SET IsDeleted = 1, LastModifiedOnDate = GETUTCDATE(), LastModifiedByUserId = @UserId
WHERE QuestionId = @Id AND PortalId = @PortalId AND IsDeleted = 0 AND IsApproved = 1 AND QuestionStatus IN (1,2);";
                    question.Parameters.Add("@Id", SqlDbType.Int).Value = questionId;
                    question.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                    question.Parameters.Add("@UserId", SqlDbType.Int).Value = UserInfo.UserID;
                    affected = question.ExecuteNonQuery();
                }

                if (affected <= 0)
                {
                    transaction.Rollback();
                    return false;
                }

                using (var responses = connection.CreateCommand())
                {
                    responses.Transaction = transaction;
                    responses.CommandText = @"
UPDATE " + ResponsesTable + @"
SET IsDeleted = 1, LastModifiedOnDate = GETUTCDATE(), LastModifiedByUserId = @UserId
WHERE QuestionId = @Id AND PortalId = @PortalId AND IsDeleted = 0;";
                    responses.Parameters.Add("@Id", SqlDbType.Int).Value = questionId;
                    responses.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
                    responses.Parameters.Add("@UserId", SqlDbType.Int).Value = UserInfo.UserID;
                    responses.ExecuteNonQuery();
                }

                transaction.Commit();
                return true;
            }
        }
    }

    private void DeleteResponse(int responseId)
    {
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
UPDATE " + ResponsesTable + @"
SET IsDeleted = 1, LastModifiedOnDate = GETUTCDATE(), LastModifiedByUserId = @UserId
WHERE ResponseId = @Id AND PortalId = @PortalId AND IsDeleted = 0;";
            AddAdminScope(command, responseId);
            connection.Open(); command.ExecuteNonQuery();
        }
    }

    private void SetQuestionStatus(int questionId, int status)
    {
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
UPDATE " + QuestionsTable + @"
SET QuestionStatus = @Status, LastModifiedOnDate = GETUTCDATE(), LastModifiedByUserId = @UserId
WHERE QuestionId = @Id AND PortalId = @PortalId AND IsDeleted = 0 AND IsApproved = 1;";
            command.Parameters.Add("@Status", SqlDbType.TinyInt).Value = status;
            AddAdminScope(command, questionId);
            connection.Open(); command.ExecuteNonQuery();
        }
    }

    private void AddAdminScope(SqlCommand command, int id)
    {
        command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
        command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
        command.Parameters.Add("@UserId", SqlDbType.Int).Value = UserInfo.UserID;
    }

    private void LoadSettings()
    {
        chkPostingEnabled.Checked = true;
        chkGuestPostingEnabled.Checked = false;
        chkRequireRegisteredModeration.Checked = true;
        chkEnableLanguageFilter.Checked = false;
        txtBlockedLanguageTerms.Text = String.Empty;
        txtMaximumQuestionLength.Text = "4000";
        txtMaximumResponseLength.Text = "4000";
        chkEnableRateLimiting.Checked = true;
        txtRateLimitSeconds.Text = "60";
        txtRateLimitMaxPosts.Text = "5";
        txtRateLimitWindowMinutes.Text = "15";
        chkEnableCaptcha.Checked = false;
        chkEnableNotifications.Checked = false;
        txtNotificationEmailAddresses.Text = String.Empty;
        chkIncludeSubmissionText.Checked = true;
        litAudit.Text = "No portal-specific Q&A settings have been saved yet; safe defaults are in use.";

        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = "SELECT * FROM " + PortalSettingsTable + " WHERE PortalId = @PortalId;";
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                if (!reader.Read()) return;
                chkPostingEnabled.Checked = ReadBool(reader, "PostingEnabled", true);
                chkGuestPostingEnabled.Checked = ReadBool(reader, "GuestPostingEnabled", false);
                chkRequireRegisteredModeration.Checked = ReadBool(reader, "RequireRegisteredModeration", true);
                chkEnableLanguageFilter.Checked = ReadBool(reader, "EnableLanguageFilter", false);
                txtBlockedLanguageTerms.Text = ReadString(reader, "BlockedLanguageTerms", String.Empty);
                txtMaximumQuestionLength.Text = ReadInt(reader, "MaximumQuestionLength", 4000).ToString();
                txtMaximumResponseLength.Text = ReadInt(reader, "MaximumResponseLength", 4000).ToString();
                chkEnableRateLimiting.Checked = ReadBool(reader, "EnableRateLimiting", true);
                txtRateLimitSeconds.Text = ReadInt(reader, "RateLimitSeconds", 60).ToString();
                txtRateLimitMaxPosts.Text = ReadInt(reader, "RateLimitMaxPosts", 5).ToString();
                txtRateLimitWindowMinutes.Text = ReadInt(reader, "RateLimitWindowMinutes", 15).ToString();
                chkEnableCaptcha.Checked = ReadBool(reader, "EnableCaptcha", false);
                chkEnableNotifications.Checked = ReadBool(reader, "EnableNotifications", false);
                txtNotificationEmailAddresses.Text = ReadString(reader, "NotificationEmailAddresses", String.Empty);
                chkIncludeSubmissionText.Checked = ReadBool(reader, "IncludeSubmissionTextInNotifications", true);
                var modified = reader["ModifiedOnDate"] == DBNull.Value ? String.Empty : Convert.ToDateTime(reader["ModifiedOnDate"]).ToLocalTime().ToString("d MMM yyyy, h:mm tt");
                var modifiedBy = reader["ModifiedByUserId"] == DBNull.Value ? String.Empty : Convert.ToString(reader["ModifiedByUserId"]);
                if (!String.IsNullOrWhiteSpace(modified)) litAudit.Text = "Last saved " + HttpUtility.HtmlEncode(modified) + (String.IsNullOrWhiteSpace(modifiedBy) ? String.Empty : " by DNN User ID " + HttpUtility.HtmlEncode(modifiedBy)) + ".";
            }
        }
    }

    protected void Tab_Command(object sender, CommandEventArgs e)
    {
        ActiveTab = Convert.ToString(e.CommandArgument);
        pnlMessage.Visible = false;
        RefreshAdministration();
    }

    protected void Pager_Command(object sender, CommandEventArgs e)
    {
        var raw = Convert.ToString(e.CommandArgument);
        var parts = (raw ?? String.Empty).Split(':');
        if (parts.Length != 2) return;
        int delta;
        if (!Int32.TryParse(parts[1], out delta) || (delta != -1 && delta != 1)) return;
        var key = NormalizeTab(parts[0]);
        if (key != TabPending && key != TabAwaiting && key != TabAnswered && key != TabClosed) return;
        SetPageIndex(key, GetPageIndex(key) + delta);
        ActiveTab = key;
        RefreshAdministration();
    }

    private string NormalizeTab(string value)
    {
        value = (value ?? String.Empty).Trim().ToLowerInvariant();
        if (value == TabPending || value == TabAwaiting || value == TabAnswered || value == TabClosed || value == TabSettings) return value;
        return TabDashboard;
    }

    private void RefreshAdministration() { RefreshAdministration(true); }
    private void RefreshAdministration(bool loadCurrentTab)
    {
        ApplyActiveTab();
        BindDashboardCounts();
        if (loadCurrentTab) BindCurrentTab();
    }

    private void BindCurrentTab()
    {
        if (ActiveTab == TabPending) BindPending();
        else if (ActiveTab == TabAwaiting) BindQuestionStatus(rptAwaiting, pnlNoAwaiting, 0, TabAwaiting, pnlAwaitingPager, btnAwaitingPrev, btnAwaitingNext, litAwaitingPage);
        else if (ActiveTab == TabAnswered) BindQuestionStatus(rptAnswered, pnlNoAnswered, 1, TabAnswered, pnlAnsweredPager, btnAnsweredPrev, btnAnsweredNext, litAnsweredPage);
        else if (ActiveTab == TabClosed) BindQuestionStatus(rptClosed, pnlNoClosed, 2, TabClosed, pnlClosedPager, btnClosedPrev, btnClosedNext, litClosedPage);
        else if (ActiveTab == TabSettings) LoadSettings();
    }

    private void ApplyActiveTab()
    {
        var tab = ActiveTab;
        pnlDashboardTab.Visible = tab == TabDashboard;
        pnlPendingTab.Visible = tab == TabPending;
        pnlAwaitingTab.Visible = tab == TabAwaiting;
        pnlAnsweredTab.Visible = tab == TabAnswered;
        pnlClosedTab.Visible = tab == TabClosed;
        pnlSettingsTab.Visible = tab == TabSettings;

        SetTabClass(tabDashboard, tab == TabDashboard);
        SetTabClass(tabPending, tab == TabPending);
        SetTabClass(tabAwaiting, tab == TabAwaiting);
        SetTabClass(tabAnswered, tab == TabAnswered);
        SetTabClass(tabClosed, tab == TabClosed);
        SetTabClass(tabSettings, tab == TabSettings);
    }

    private static void SetTabClass(LinkButton button, bool active)
    {
        if (button == null) return;
        button.CssClass = active ? "jqa-admin-tab jqa-admin-tab-active" : "jqa-admin-tab";
    }

    private void BindDashboardCounts()
    {
        int pending = 0, awaiting = 0, answered = 0, closed = 0;
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT
    (SELECT COUNT(*) FROM " + QuestionsTable + @" WHERE PortalId=@PortalId AND IsDeleted=0 AND IsApproved=0) +
    (SELECT COUNT(*) FROM " + ResponsesTable + @" R INNER JOIN " + QuestionsTable + @" Q ON Q.QuestionId=R.QuestionId AND Q.PortalId=R.PortalId WHERE R.PortalId=@PortalId AND R.IsDeleted=0 AND R.IsApproved=0 AND Q.IsDeleted=0) AS PendingCount,
    (SELECT COUNT(*) FROM " + QuestionsTable + @" WHERE PortalId=@PortalId AND IsDeleted=0 AND IsApproved=1 AND QuestionStatus=0) AS AwaitingCount,
    (SELECT COUNT(*) FROM " + QuestionsTable + @" WHERE PortalId=@PortalId AND IsDeleted=0 AND IsApproved=1 AND QuestionStatus=1) AS AnsweredCount,
    (SELECT COUNT(*) FROM " + QuestionsTable + @" WHERE PortalId=@PortalId AND IsDeleted=0 AND IsApproved=1 AND QuestionStatus=2) AS ClosedCount;";
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                if (reader.Read())
                {
                    pending = Convert.ToInt32(reader["PendingCount"]);
                    awaiting = Convert.ToInt32(reader["AwaitingCount"]);
                    answered = Convert.ToInt32(reader["AnsweredCount"]);
                    closed = Convert.ToInt32(reader["ClosedCount"]);
                }
            }
        }

        litDashboardPending.Text = pending.ToString();
        litDashboardAwaiting.Text = awaiting.ToString();
        litDashboardAnswered.Text = answered.ToString();
        litDashboardClosed.Text = closed.ToString();
        litPendingCount.Text = pending.ToString();
        tabPending.Text = "Pending Moderation (" + pending + ")";
        tabAwaiting.Text = "Awaiting Answer (" + awaiting + ")";
        tabAnswered.Text = "Answered (" + answered + ")";
        tabClosed.Text = "Closed (" + closed + ")";
    }

    private int CountPending()
    {
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT
    (SELECT COUNT(*) FROM " + QuestionsTable + @" WHERE PortalId=@PortalId AND IsDeleted=0 AND IsApproved=0) +
    (SELECT COUNT(*) FROM " + ResponsesTable + @" R INNER JOIN " + QuestionsTable + @" Q ON Q.QuestionId=R.QuestionId AND Q.PortalId=R.PortalId WHERE R.PortalId=@PortalId AND R.IsDeleted=0 AND R.IsApproved=0 AND Q.IsDeleted=0);";
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            connection.Open();
            return Convert.ToInt32(command.ExecuteScalar());
        }
    }

    private void BindPending()
    {
        var total = CountPending();
        var pageIndex = ClampPageIndex(total, GetPageIndex(TabPending));
        SetPageIndex(TabPending, pageIndex);
        var rows = new List<PendingRow>();
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT ItemType, ItemId, TabId, ModuleId, Title, DisplayName, SubmissionText, IsLanguageFlagged, CreatedOnDate, ResponseType
FROM (
    SELECT 'Q' AS ItemType, QuestionId AS ItemId, TabId, ModuleId, QuestionTitle AS Title,
           DisplayName, QuestionText AS SubmissionText, IsLanguageFlagged, CreatedOnDate, 0 AS ResponseType
    FROM " + QuestionsTable + @"
    WHERE PortalId = @PortalId AND IsDeleted = 0 AND IsApproved = 0
    UNION ALL
    SELECT 'R' AS ItemType, R.ResponseId AS ItemId, R.TabId, R.ModuleId, Q.QuestionTitle AS Title,
           R.DisplayName, R.ResponseText AS SubmissionText, R.IsLanguageFlagged, R.CreatedOnDate, R.ResponseType
    FROM " + ResponsesTable + @" R
    INNER JOIN " + QuestionsTable + @" Q ON Q.QuestionId = R.QuestionId AND Q.PortalId = R.PortalId
    WHERE R.PortalId = @PortalId AND R.IsDeleted = 0 AND R.IsApproved = 0 AND Q.IsDeleted = 0
) P
ORDER BY CreatedOnDate ASC, ItemType ASC, ItemId ASC
OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;";
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@Offset", SqlDbType.Int).Value = pageIndex * AdminPageSize;
            command.Parameters.Add("@PageSize", SqlDbType.Int).Value = AdminPageSize;
            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                while (reader.Read())
                {
                    var type = Convert.ToString(reader["ItemType"]);
                    var responseType = Convert.ToInt32(reader["ResponseType"]);
                    rows.Add(new PendingRow {
                        Key = type + ":" + Convert.ToInt32(reader["ItemId"]),
                        Kind = type == "Q" ? "Question" : (responseType == 1 ? "Ministry Answer" : "Follow-up"),
                        Title = Convert.ToString(reader["Title"]),
                        DisplayName = Convert.ToString(reader["DisplayName"]),
                        SubmissionText = Convert.ToString(reader["SubmissionText"]),
                        IsLanguageFlagged = Convert.ToBoolean(reader["IsLanguageFlagged"]),
                        CreatedOnDate = Convert.ToDateTime(reader["CreatedOnDate"]),
                        PageUrl = BuildPageUrl(Convert.ToInt32(reader["TabId"]), Convert.ToInt32(reader["ModuleId"]), 0, false)
                    });
                }
            }
        }
        rptPending.DataSource = rows;
        rptPending.DataBind();
        pnlNoPending.Visible = total == 0;
        UpdatePager(pnlPendingPager, btnPendingPrev, btnPendingNext, litPendingPage, total, pageIndex);
    }

    private void BindQuestionStatus(Repeater repeater, Panel emptyPanel, int status, string pageKey, Panel pagerPanel, LinkButton previous, LinkButton next, Literal pageInfo)
    {
        int total;
        using (var connection = new SqlConnection(ConnectionString))
        using (var count = connection.CreateCommand())
        {
            count.CommandText = "SELECT COUNT(*) FROM " + QuestionsTable + " WHERE PortalId=@PortalId AND IsDeleted=0 AND IsApproved=1 AND QuestionStatus=@Status;";
            count.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            count.Parameters.Add("@Status", SqlDbType.TinyInt).Value = status;
            connection.Open();
            total = Convert.ToInt32(count.ExecuteScalar());
        }

        var pageIndex = ClampPageIndex(total, GetPageIndex(pageKey));
        SetPageIndex(pageKey, pageIndex);
        var rows = new List<QuestionAdminRow>();
        using (var connection = new SqlConnection(ConnectionString))
        using (var command = connection.CreateCommand())
        {
            command.CommandText = @"
SELECT QuestionId, TabId, ModuleId, QuestionTitle, DisplayName, CreatedOnDate
FROM " + QuestionsTable + @"
WHERE PortalId = @PortalId AND IsDeleted = 0 AND IsApproved = 1 AND QuestionStatus = @Status
ORDER BY CreatedOnDate DESC, QuestionId DESC
OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;";
            command.Parameters.Add("@PortalId", SqlDbType.Int).Value = PortalId;
            command.Parameters.Add("@Status", SqlDbType.TinyInt).Value = status;
            command.Parameters.Add("@Offset", SqlDbType.Int).Value = pageIndex * AdminPageSize;
            command.Parameters.Add("@PageSize", SqlDbType.Int).Value = AdminPageSize;
            connection.Open();
            using (var reader = command.ExecuteReader())
            {
                while (reader.Read())
                {
                    var id = Convert.ToInt32(reader["QuestionId"]);
                    rows.Add(new QuestionAdminRow {
                        QuestionId = id,
                        Title = Convert.ToString(reader["QuestionTitle"]),
                        DisplayName = Convert.ToString(reader["DisplayName"]),
                        CreatedOnDate = Convert.ToDateTime(reader["CreatedOnDate"]),
                        PageUrl = BuildPageUrl(Convert.ToInt32(reader["TabId"]), Convert.ToInt32(reader["ModuleId"]), id, status == 0)
                    });
                }
            }
        }
        repeater.DataSource = rows;
        repeater.DataBind();
        emptyPanel.Visible = total == 0;
        UpdatePager(pagerPanel, previous, next, pageInfo, total, pageIndex);
    }

    private static int ClampPageIndex(int total, int requested)
    {
        if (total <= 0) return 0;
        var last = Math.Max(0, (total - 1) / AdminPageSize);
        return Math.Max(0, Math.Min(last, requested));
    }

    private static void UpdatePager(Panel panel, LinkButton previous, LinkButton next, Literal pageInfo, int total, int pageIndex)
    {
        var pages = total <= 0 ? 1 : ((total - 1) / AdminPageSize) + 1;
        panel.Visible = total > AdminPageSize;
        previous.Enabled = pageIndex > 0;
        next.Enabled = pageIndex + 1 < pages;
        pageInfo.Text = "Page " + (pageIndex + 1) + " of " + pages + " · " + total + " item" + (total == 1 ? String.Empty : "s");
    }

    private string BuildPageUrl(int tabId, int moduleId, int questionId, bool openAnswer)
    {
        if (questionId <= 0) return DotNetNuke.Common.Globals.NavigateURL(tabId);

        string url;
        if (openAnswer)
        {
            url = DotNetNuke.Common.Globals.NavigateURL(
                tabId,
                String.Empty,
                AnswerQuestionQueryKey + "=" + questionId,
                AnswerModuleQueryKey + "=" + moduleId,
                AnswerActionQueryKey + "=answer");
        }
        else
        {
            url = DotNetNuke.Common.Globals.NavigateURL(tabId);
        }

        return url + "#jqa-question-" + questionId;
    }

    protected string Encode(object value) { return HttpUtility.HtmlEncode(Convert.ToString(value)); }
    protected string FormatDate(object value) { return Convert.ToDateTime(value).ToLocalTime().ToString("d MMM yyyy, h:mm tt"); }
    protected bool ShowLanguageFlag(object value) { try { return Convert.ToBoolean(value); } catch { return false; } }

    private void EnsureSecurityToken() { EnsureSecurityToken(false); }
    private void EnsureSecurityToken(bool rotate)
    {
        if (Session == null) return;
        var token = rotate ? String.Empty : Convert.ToString(Session[SecurityTokenSessionKey]);
        if (String.IsNullOrWhiteSpace(token))
        {
            var bytes = new byte[32];
            using (var rng = RandomNumberGenerator.Create()) rng.GetBytes(bytes);
            token = Convert.ToBase64String(bytes);
            Session[SecurityTokenSessionKey] = token;
        }
        hdnSecurityToken.Value = token;
    }

    private bool ValidateSecurityToken()
    {
        if (Session == null) return false;
        return SecureEquals(Convert.ToString(Session[SecurityTokenSessionKey]), hdnSecurityToken.Value);
    }

    private static bool SecureEquals(string a, string b)
    {
        if (String.IsNullOrEmpty(a) || String.IsNullOrEmpty(b)) return false;
        var x = Encoding.UTF8.GetBytes(a); var y = Encoding.UTF8.GetBytes(b);
        var diff = x.Length ^ y.Length; var len = Math.Max(x.Length, y.Length);
        for (var i = 0; i < len; i++) diff |= (i < x.Length ? x[i] : (byte)0) ^ (i < y.Length ? y[i] : (byte)0);
        return diff == 0;
    }

    private void ShowMessage(string message, bool success)
    {
        pnlMessage.Visible = true;
        pnlMessage.CssClass = success ? "jqa-message jqa-message-success" : "jqa-message jqa-message-error";
        litMessage.Text = HttpUtility.HtmlEncode(message);
    }

    private string NormalizeBlockedTerms(string raw)
    {
        var output = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var part in (raw ?? String.Empty).Replace("\r\n", "\n").Replace('\r','\n').Split(new[] {'\n'}, StringSplitOptions.RemoveEmptyEntries))
        {
            var term = part.Trim();
            if (term.Length == 0) continue;
            if (term.Length > MaximumBlockedTermLength) term = term.Substring(0, MaximumBlockedTermLength);
            if (seen.Add(term)) output.Add(term);
            if (output.Count >= MaximumBlockedTermCount) break;
        }
        return String.Join("\r\n", output.ToArray());
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
        foreach (var c in value) if (!(Char.IsLetterOrDigit(c) || c == '_')) return defaultValue ?? String.Empty;
        return value;
    }

    private static int ParseInt(string value, int d, int min, int max) { int n; return Int32.TryParse((value ?? String.Empty).Trim(), out n) ? Math.Max(min, Math.Min(max, n)) : d; }
    private static string Truncate(string value, int max) { value = value ?? String.Empty; return value.Length <= max ? value : value.Substring(0, max); }
    private static bool ReadBool(IDataRecord r, string name, bool d) { try { return r[name] == DBNull.Value ? d : Convert.ToBoolean(r[name]); } catch { return d; } }
    private static int ReadInt(IDataRecord r, string name, int d) { try { return r[name] == DBNull.Value ? d : Convert.ToInt32(r[name]); } catch { return d; } }
    private static string ReadString(IDataRecord r, string name, string d) { try { return r[name] == DBNull.Value ? d : Convert.ToString(r[name]); } catch { return d; } }

    protected sealed class PendingRow
    {
        public string Key { get; set; }
        public string Kind { get; set; }
        public string Title { get; set; }
        public string DisplayName { get; set; }
        public string SubmissionText { get; set; }
        public bool IsLanguageFlagged { get; set; }
        public DateTime CreatedOnDate { get; set; }
        public string PageUrl { get; set; }
    }

    protected sealed class QuestionAdminRow
    {
        public int QuestionId { get; set; }
        public string Title { get; set; }
        public string DisplayName { get; set; }
        public DateTime CreatedOnDate { get; set; }
        public string PageUrl { get; set; }
    }
</script>

<div class="jacaranda-qa jqa-administration">
    <asp:Panel ID="pnlAccessDenied" runat="server" Visible="false" CssClass="jqa-message jqa-message-error">
        Q&amp;A Administration is available only to a DNN portal Administrator or Superuser.
    </asp:Panel>

    <asp:Panel ID="pnlAdministration" runat="server" Visible="false">
        <h2><%= HttpUtility.HtmlEncode(QaSiteTitle) %> Q&amp;A Administration</h2>
        <p class="jqa-intro">Moderate theological questions and follow-ups, identify conversations awaiting an answer, and manage the portal-wide Q&amp;A configuration.</p>

        <asp:Panel ID="pnlMessage" runat="server" Visible="false" CssClass="jqa-message" role="status" aria-live="polite">
            <asp:Literal ID="litMessage" runat="server" />
        </asp:Panel>
        <asp:HiddenField ID="hdnSecurityToken" runat="server" />

        <nav class="jqa-admin-tabs" aria-label="Q&amp;A administration sections">
            <asp:LinkButton ID="tabDashboard" runat="server" Text="Dashboard" CommandArgument="dashboard" OnCommand="Tab_Command" CausesValidation="false" />
            <asp:LinkButton ID="tabPending" runat="server" Text="Pending Moderation" CommandArgument="pending" OnCommand="Tab_Command" CausesValidation="false" />
            <asp:LinkButton ID="tabAwaiting" runat="server" Text="Awaiting Answer" CommandArgument="awaiting" OnCommand="Tab_Command" CausesValidation="false" />
            <asp:LinkButton ID="tabAnswered" runat="server" Text="Answered" CommandArgument="answered" OnCommand="Tab_Command" CausesValidation="false" />
            <asp:LinkButton ID="tabClosed" runat="server" Text="Closed" CommandArgument="closed" OnCommand="Tab_Command" CausesValidation="false" />
            <asp:LinkButton ID="tabSettings" runat="server" Text="Settings" CommandArgument="settings" OnCommand="Tab_Command" CausesValidation="false" />
        </nav>

        <asp:Panel ID="pnlDashboardTab" runat="server" Visible="false">
            <section class="jqa-admin-section">
                <h3>Dashboard</h3>
                <div class="jqa-dashboard-grid">
                    <div class="jqa-dashboard-card"><strong><asp:Literal ID="litDashboardPending" runat="server" /></strong><span>Pending Moderation</span><asp:LinkButton ID="dashPending" runat="server" Text="Open" CommandArgument="pending" OnCommand="Tab_Command" CausesValidation="false" CssClass="jqa-secondary-button" /></div>
                    <div class="jqa-dashboard-card"><strong><asp:Literal ID="litDashboardAwaiting" runat="server" /></strong><span>Awaiting Answer</span><asp:LinkButton ID="dashAwaiting" runat="server" Text="Open" CommandArgument="awaiting" OnCommand="Tab_Command" CausesValidation="false" CssClass="jqa-secondary-button" /></div>
                    <div class="jqa-dashboard-card"><strong><asp:Literal ID="litDashboardAnswered" runat="server" /></strong><span>Answered</span><asp:LinkButton ID="dashAnswered" runat="server" Text="Open" CommandArgument="answered" OnCommand="Tab_Command" CausesValidation="false" CssClass="jqa-secondary-button" /></div>
                    <div class="jqa-dashboard-card"><strong><asp:Literal ID="litDashboardClosed" runat="server" /></strong><span>Closed</span><asp:LinkButton ID="dashClosed" runat="server" Text="Open" CommandArgument="closed" OnCommand="Tab_Command" CausesValidation="false" CssClass="jqa-secondary-button" /></div>
                </div>
                <p class="jqa-help">Select a dashboard card or one of the tabs above. Historical lists are paged at 20 questions per page so administration remains manageable as the archive grows.</p>
            </section>
        </asp:Panel>

        <asp:Panel ID="pnlPendingTab" runat="server" Visible="false">
            <section class="jqa-admin-section">
                <h3>Pending Moderation <span class="jqa-count"><asp:Literal ID="litPendingCount" runat="server" /></span></h3>
                <asp:Panel ID="pnlNoPending" runat="server" Visible="false" CssClass="jqa-empty">There are no submissions awaiting moderation.</asp:Panel>
                <asp:Repeater ID="rptPending" runat="server" OnItemCommand="rptPending_ItemCommand">
                    <ItemTemplate>
                        <article class="jqa-admin-item">
                            <div class="jqa-admin-item-header">
                                <strong><%# Encode(Eval("Kind")) %>: <%# Encode(Eval("Title")) %></strong>
                                <span><%# FormatDate(Eval("CreatedOnDate")) %></span>
                            </div>
                            <div class="jqa-meta">From <%# Encode(Eval("DisplayName")) %></div>
                            <asp:Label ID="lblLanguageFlag" runat="server" CssClass="jqa-language-flag" Text="Language filter" Visible='<%# ShowLanguageFlag(Eval("IsLanguageFlagged")) %>' />
                            <div class="jqa-admin-text"><%# Encode(Eval("SubmissionText")) %></div>
                            <div class="jqa-actions">
                                <asp:LinkButton ID="btnApprove" runat="server" CommandName="Approve" CommandArgument='<%# Eval("Key") %>' Text="Approve" CssClass="jqa-submit" CausesValidation="false" />
                                <asp:LinkButton ID="btnDelete" runat="server" CommandName="Delete" CommandArgument='<%# Eval("Key") %>' Text="Reject / Delete" CssClass="jqa-danger-button" CausesValidation="false" OnClientClick="return confirm('Reject and soft-delete this submission?');" />
                                <asp:HyperLink ID="lnkPage" runat="server" NavigateUrl='<%# Eval("PageUrl") %>' Text="View Page" CssClass="jqa-secondary-button" />
                            </div>
                        </article>
                    </ItemTemplate>
                </asp:Repeater>
                <asp:Panel ID="pnlPendingPager" runat="server" Visible="false" CssClass="jqa-pager">
                    <asp:LinkButton ID="btnPendingPrev" runat="server" Text="Previous" CommandArgument="pending:-1" OnCommand="Pager_Command" CausesValidation="false" CssClass="jqa-secondary-button" />
                    <span><asp:Literal ID="litPendingPage" runat="server" /></span>
                    <asp:LinkButton ID="btnPendingNext" runat="server" Text="Next" CommandArgument="pending:1" OnCommand="Pager_Command" CausesValidation="false" CssClass="jqa-secondary-button" />
                </asp:Panel>
            </section>
        </asp:Panel>

        <asp:Panel ID="pnlAwaitingTab" runat="server" Visible="false">
            <section class="jqa-admin-section">
                <h3>Questions Awaiting Answer</h3>
                <asp:Panel ID="pnlNoAwaiting" runat="server" Visible="false" CssClass="jqa-empty">There are no approved questions awaiting an answer.</asp:Panel>
                <asp:Repeater ID="rptAwaiting" runat="server" OnItemCommand="rptQuestions_ItemCommand">
                    <ItemTemplate>
                        <div class="jqa-admin-question-row">
                            <div><strong><%# Encode(Eval("Title")) %></strong><br /><span class="jqa-meta"><%# Encode(Eval("DisplayName")) %> · <%# FormatDate(Eval("CreatedOnDate")) %></span></div>
                            <div class="jqa-actions">
                                <asp:HyperLink ID="lnkView" runat="server" NavigateUrl='<%# Eval("PageUrl") %>' Text="View / Answer" CssClass="jqa-submit" />
                                <asp:LinkButton ID="btnClose" runat="server" CommandName="Close" CommandArgument='<%# Eval("QuestionId") %>' Text="Close" CssClass="jqa-secondary-button" CausesValidation="false" />
                            </div>
                        </div>
                    </ItemTemplate>
                </asp:Repeater>
                <asp:Panel ID="pnlAwaitingPager" runat="server" Visible="false" CssClass="jqa-pager">
                    <asp:LinkButton ID="btnAwaitingPrev" runat="server" Text="Previous" CommandArgument="awaiting:-1" OnCommand="Pager_Command" CausesValidation="false" CssClass="jqa-secondary-button" />
                    <span><asp:Literal ID="litAwaitingPage" runat="server" /></span>
                    <asp:LinkButton ID="btnAwaitingNext" runat="server" Text="Next" CommandArgument="awaiting:1" OnCommand="Pager_Command" CausesValidation="false" CssClass="jqa-secondary-button" />
                </asp:Panel>
            </section>
        </asp:Panel>

        <asp:Panel ID="pnlAnsweredTab" runat="server" Visible="false">
            <section class="jqa-admin-section">
                <h3>Answered Questions</h3>
                <asp:Panel ID="pnlNoAnswered" runat="server" Visible="false" CssClass="jqa-empty">There are no answered questions yet.</asp:Panel>
                <asp:Repeater ID="rptAnswered" runat="server" OnItemCommand="rptQuestions_ItemCommand">
                    <ItemTemplate>
                        <div class="jqa-admin-question-row">
                            <div><strong><%# Encode(Eval("Title")) %></strong><br /><span class="jqa-meta"><%# Encode(Eval("DisplayName")) %> · <%# FormatDate(Eval("CreatedOnDate")) %></span></div>
                            <div class="jqa-actions">
                                <asp:HyperLink ID="lnkView" runat="server" NavigateUrl='<%# Eval("PageUrl") %>' Text="View" CssClass="jqa-secondary-button" />
                                <asp:LinkButton ID="btnClose" runat="server" CommandName="Close" CommandArgument='<%# Eval("QuestionId") %>' Text="Close" CssClass="jqa-secondary-button" CausesValidation="false" />
                                <asp:LinkButton ID="btnDeleteFinished" runat="server" CommandName="DeleteFinished" CommandArgument='<%# Eval("QuestionId") %>' Text="Delete" CssClass="jqa-danger-button" CausesValidation="false" OnClientClick="return confirm('Delete this finished question and all of its responses? This will remove it from the public Q&A and administration lists.');" />
                            </div>
                        </div>
                    </ItemTemplate>
                </asp:Repeater>
                <asp:Panel ID="pnlAnsweredPager" runat="server" Visible="false" CssClass="jqa-pager">
                    <asp:LinkButton ID="btnAnsweredPrev" runat="server" Text="Previous" CommandArgument="answered:-1" OnCommand="Pager_Command" CausesValidation="false" CssClass="jqa-secondary-button" />
                    <span><asp:Literal ID="litAnsweredPage" runat="server" /></span>
                    <asp:LinkButton ID="btnAnsweredNext" runat="server" Text="Next" CommandArgument="answered:1" OnCommand="Pager_Command" CausesValidation="false" CssClass="jqa-secondary-button" />
                </asp:Panel>
            </section>
        </asp:Panel>

        <asp:Panel ID="pnlClosedTab" runat="server" Visible="false">
            <section class="jqa-admin-section">
                <h3>Closed Questions</h3>
                <asp:Panel ID="pnlNoClosed" runat="server" Visible="false" CssClass="jqa-empty">There are no closed questions.</asp:Panel>
                <asp:Repeater ID="rptClosed" runat="server" OnItemCommand="rptQuestions_ItemCommand">
                    <ItemTemplate>
                        <div class="jqa-admin-question-row">
                            <div><strong><%# Encode(Eval("Title")) %></strong><br /><span class="jqa-meta"><%# Encode(Eval("DisplayName")) %> · <%# FormatDate(Eval("CreatedOnDate")) %></span></div>
                            <div class="jqa-actions">
                                <asp:HyperLink ID="lnkView" runat="server" NavigateUrl='<%# Eval("PageUrl") %>' Text="View" CssClass="jqa-secondary-button" />
                                <asp:LinkButton ID="btnReopen" runat="server" CommandName="Reopen" CommandArgument='<%# Eval("QuestionId") %>' Text="Reopen as Awaiting Answer" CssClass="jqa-secondary-button" CausesValidation="false" />
                                <asp:LinkButton ID="btnDeleteFinished" runat="server" CommandName="DeleteFinished" CommandArgument='<%# Eval("QuestionId") %>' Text="Delete" CssClass="jqa-danger-button" CausesValidation="false" OnClientClick="return confirm('Delete this finished question and all of its responses? This will remove it from the public Q&A and administration lists.');" />
                            </div>
                        </div>
                    </ItemTemplate>
                </asp:Repeater>
                <asp:Panel ID="pnlClosedPager" runat="server" Visible="false" CssClass="jqa-pager">
                    <asp:LinkButton ID="btnClosedPrev" runat="server" Text="Previous" CommandArgument="closed:-1" OnCommand="Pager_Command" CausesValidation="false" CssClass="jqa-secondary-button" />
                    <span><asp:Literal ID="litClosedPage" runat="server" /></span>
                    <asp:LinkButton ID="btnClosedNext" runat="server" Text="Next" CommandArgument="closed:1" OnCommand="Pager_Command" CausesValidation="false" CssClass="jqa-secondary-button" />
                </asp:Panel>
            </section>
        </asp:Panel>

        <asp:Panel ID="pnlSettingsTab" runat="server" Visible="false">
            <section class="jqa-admin-section jqa-settings-section">
                <h3>Portal-wide Q&amp;A Settings</h3>
                <fieldset>
                    <legend>Participation and moderation</legend>
                    <div class="jqa-checkbox"><asp:CheckBox ID="chkPostingEnabled" runat="server" Text="Allow new questions and responses anywhere on this portal" /></div>
                    <div class="jqa-checkbox"><asp:CheckBox ID="chkGuestPostingEnabled" runat="server" Text="Allow guests to ask questions" /></div>
                    <div class="jqa-checkbox"><asp:CheckBox ID="chkRequireRegisteredModeration" runat="server" Text="Hold registered-questioner questions and follow-ups for moderation" /></div>
                    <p class="jqa-help">Guest questions and guest follow-ups are always moderated. Ministry answers are always approved immediately.</p>
                </fieldset>

                <fieldset>
                    <legend>Language and length</legend>
                    <div class="jqa-checkbox"><asp:CheckBox ID="chkEnableLanguageFilter" runat="server" Text="Enable the private language filter" /></div>
                    <div class="jqa-field">
                        <asp:Label ID="lblBlockedLanguageTerms" runat="server" AssociatedControlID="txtBlockedLanguageTerms" Text="Private language-filter terms (one per line)" />
                        <asp:TextBox ID="txtBlockedLanguageTerms" runat="server" TextMode="MultiLine" Rows="7" CssClass="jqa-textarea" />
                    </div>
                    <div class="jqa-setting-grid">
                        <div class="jqa-field"><asp:Label ID="lblMaximumQuestionLength" runat="server" AssociatedControlID="txtMaximumQuestionLength" Text="Maximum question characters" /><asp:TextBox ID="txtMaximumQuestionLength" runat="server" CssClass="jqa-small-input" MaxLength="5" /></div>
                        <div class="jqa-field"><asp:Label ID="lblMaximumResponseLength" runat="server" AssociatedControlID="txtMaximumResponseLength" Text="Maximum response characters" /><asp:TextBox ID="txtMaximumResponseLength" runat="server" CssClass="jqa-small-input" MaxLength="5" /></div>
                    </div>
                </fieldset>

                <fieldset>
                    <legend>Anti-spam</legend>
                    <div class="jqa-checkbox"><asp:CheckBox ID="chkEnableRateLimiting" runat="server" Text="Enable rate limiting for questioners" /></div>
                    <div class="jqa-setting-grid">
                        <div class="jqa-field"><asp:Label ID="lblRateLimitSeconds" runat="server" AssociatedControlID="txtRateLimitSeconds" Text="Minimum seconds between posts" /><asp:TextBox ID="txtRateLimitSeconds" runat="server" CssClass="jqa-small-input" MaxLength="4" /></div>
                        <div class="jqa-field"><asp:Label ID="lblRateLimitMaxPosts" runat="server" AssociatedControlID="txtRateLimitMaxPosts" Text="Maximum posts per window" /><asp:TextBox ID="txtRateLimitMaxPosts" runat="server" CssClass="jqa-small-input" MaxLength="3" /></div>
                        <div class="jqa-field"><asp:Label ID="lblRateLimitWindowMinutes" runat="server" AssociatedControlID="txtRateLimitWindowMinutes" Text="Window length in minutes" /><asp:TextBox ID="txtRateLimitWindowMinutes" runat="server" CssClass="jqa-small-input" MaxLength="4" /></div>
                    </div>
                    <div class="jqa-checkbox"><asp:CheckBox ID="chkEnableCaptcha" runat="server" Text="Enable the built-in arithmetic CAPTCHA for questioners" /></div>
                </fieldset>

                <fieldset>
                    <legend>Email notifications</legend>
                    <div class="jqa-checkbox"><asp:CheckBox ID="chkEnableNotifications" runat="server" Text="Enable Q&amp;A email notifications: alert administrators to new questions/follow-ups and notify questioners when answers are posted" /></div>
                    <div class="jqa-field"><asp:Label ID="lblNotificationEmailAddresses" runat="server" AssociatedControlID="txtNotificationEmailAddresses" Text="Administrator notification email address(es)" /><asp:TextBox ID="txtNotificationEmailAddresses" runat="server" TextMode="MultiLine" Rows="3" CssClass="jqa-textarea" MaxLength="2000" /></div>
                    <div class="jqa-checkbox"><asp:CheckBox ID="chkIncludeSubmissionText" runat="server" Text="Include visitor-submitted text in administrator notification emails" /></div>
                </fieldset>

                <div class="jqa-audit-note"><asp:Literal ID="litAudit" runat="server" /></div>
                <div class="jqa-actions">
                    <asp:Button ID="btnSave" runat="server" Text="Save Q&amp;A Settings" CssClass="jqa-submit" OnClick="btnSave_Click" OnClientClick="return confirm('Save these portal-wide Jacaranda Q&A settings?');" />
                </div>
            </section>
        </asp:Panel>
    </asp:Panel>
</div>
