# Jacaranda Q&A

Jacaranda Q&A is an independent DNN 10 WebForms module for moderated theological question-and-answer ministry.

## Version

01.00.16 — Dynamic site-title Administration heading.

## Physical path

`DesktopModules/JacarandaQandA`

## DNN modules installed

The installation ZIP now registers two separate DNN DesktopModules/packages while sharing the same runtime files and Q&A database:

- **Jacaranda Q&A** — public question-and-answer module.
- **Jacaranda Q&A Administration** — separately placeable central moderation, status-management and portal-settings module.

This corrects the 01.00.03 packaging approach, which used a second ModuleDefinition under the public DesktopModule and therefore did not produce a separate item in DNN's Add Module picker.

The Administration module can be placed on a normal DNN page whose page/module permissions are restricted to Administrators. Administration.ascx also enforces portal Administrator/Superuser authorization server-side.

Administrators and Superusers continue to see the administration toolbar on public Jacaranda Q&A instances, including Pending Moderation and Awaiting Answer counts and direct administration access without entering Edit Mode.

## Runtime independence

Jacaranda Q&A has its own DNN package identity, controls, CSS, database tables and settings. It does not use Jacaranda Comments tables at runtime.

## Core conversation model

- A visitor submits a Question.
- Moderation controls whether it becomes public.
- A portal Administrator or Superuser posts the ministry Answer.
- The original questioner can submit a Follow-up.
- An approved follow-up returns the Question to Awaiting Answer.
- A ministry answer marks the Question Answered.
- Administrators can Close or reopen a Question.

## Status values

Questions: 0 Awaiting Answer, 1 Answered, 2 Closed.
Responses: 1 Ministry Answer, 2 Questioner Follow-up.

## Security

All browser input is validated server-side. SQL values are parameterised. Portal/page/module identity is derived from DNN context. Guest email remains private. Guest participation is optional and moderated. Administration remains restricted server-side to the portal Administrators role and DNN Superusers.


## 01.00.05 administration navigation

When a `Jacaranda Q&A Administration` module has been placed on a DNN page, the administrator-only toolbar on a public Q&A module automatically discovers that page and opens it directly. The legacy internal Administration control remains only as a fallback when no standalone administration placement exists.

All Jacaranda Q&A module surfaces use `#F5F5DC` as the eye-relief background colour; input controls remain white for clear form contrast.


## 01.00.06 administration workflow

The standalone Administration module now uses a tabbed layout: Dashboard, Pending Moderation, Awaiting Answer, Answered, Closed and Settings. This keeps portal settings at the top of the administration workflow instead of below an ever-growing question history.

Pending, awaiting, answered and closed lists are paginated at 20 items per page using server-side SQL paging. The Dashboard provides live counts and quick links into each operational queue.

Answered and Closed questions include a Delete action with confirmation. The action is enforced again server-side and only succeeds when the question is approved and currently Answered or Closed. Deletion is soft deletion: the Question and all related Responses are marked deleted together and removed from public/admin lists without physically dropping the database rows.


## 01.00.07 focused answer workflow

When an Administrator or Superuser selects **View / Answer** from Q&A Administration, the public Q&A module now enters a focused answer mode. The normal **Ask a Question** section is hidden, only the selected question and its existing responses are displayed, and the answer form appears immediately after that conversation. The heading changes to **Question to Answer** so the purpose of the view is clear.

The same focused presentation is used when an Administrator selects **Answer** directly from a public question. Cancelling the response returns to the normal **Questions & Answers** view. No database schema changes are required.


## 01.00.08 compact question entry

The normal public Q&A page now keeps the full question-entry form collapsed by default. A prominent **Ask a Question** button appears near the top of the module; selecting it expands the form and moves focus to the question-entry region.

Selecting **Close Question Form** collapses the form again. Validation errors keep the form open so the visitor can correct the submission. After a successful submission the form returns to its collapsed state.

Focused Administrator answer mode continues to hide the public Ask a Question area completely. No database schema changes are required.


## 01.00.09 inline follow-up workflow

Selecting **Ask a follow-up** now places the follow-up editor directly inside the selected question conversation, after its existing answers/follow-ups and question actions, instead of rendering the editor at the bottom of the complete Q&A page. The browser moves directly to the follow-up editor.

The shared response editor uses the same question-attached placement for Administrator answers while retaining the focused-answer behaviour introduced in 01.00.07. Response validation errors re-attach and refocus the editor on the selected conversation so the visitor is not sent back to the bottom of the page. No database schema changes are required.


## 01.00.10 guest correction and participation guidance

New guest questions that are awaiting moderation now receive a secure **5-minute correction window**. Immediately after submission, the guest is shown the title and question text they submitted and may correct those two fields while the window remains open. The guest's public name and private email cannot be changed.

The correction right uses a separate cryptographically random session credential from the longer-lived guest conversation credential. Only a scoped SHA-256 hash is stored in `GuestEditTokenHash`. Every correction is revalidated server-side against the question ID, portal, page, module, guest ownership token, moderation state, deletion state and original creation time. Once the five-minute window expires or the question is approved, correction is no longer accepted.

The public module now also explains the participation model before a visitor opens the question form: **please ask one question at a time**; Jacaranda Q&A is a moderated question-and-answer ministry rather than an open discussion forum; after an answer is posted, the original questioner may ask a related follow-up.

The **Ask a follow-up** control is now shown only when the question status is **Answered** and the current visitor is verified as the original registered or guest questioner. No database schema changes are required because the guest edit-token field was included in the original 01.00.00 schema.


## 01.00.11 one-shot correction and collapsed archive

A guest still has up to five minutes after submitting a moderated question to review it, but the correction opportunity is now **single-use**. Saving one correction atomically clears the stored guest edit-token hash, clears the session credential and returns the visitor to the normal Q&A page with a confirmation. Further corrections are not accepted even if time remains.

On a normal first visit, published Q&A conversations are collapsed to their **question title and status**. Selecting a question title expands that conversation; opening another question collapses the previously open one. The title control exposes its expanded/collapsed state for assistive technology.

Focused Administrator Answer mode, follow-up actions, post-completion links and direct question/hash links automatically expand the relevant conversation so the action remains attached to its question. No database schema changes are required.


## 01.00.12 security and workflow hardening

Moderator notification emails are now forced to **plain text** so visitor-supplied content cannot trigger DNN's automatic HTML-body detection.

Guest rate limiting now uses a persistent cryptographically random browser identity rather than the browser User-Agent. The browser identity is stored in an HttpOnly, SameSite=Lax cookie and a portal-scoped SHA-256 rate key is stored with guest submissions. Existing guest conversation cookies remain supported as a compatibility fallback when enforcing active-question ownership.

The public workflow now enforces **one active question at a time** on the server. A registered user or recognised guest cannot create another top-level question while one of their questions is awaiting moderation/answer, or while one of their follow-ups is awaiting moderation. Once the earlier question is Answered with no pending follow-up, another top-level question may be asked. The final insert repeats this check inside a serializable database transaction to reduce double-submit/race conditions.

Only one pending questioner follow-up is permitted per question. The follow-up button is suppressed while a follow-up awaits moderation, and the response insert rechecks status and pending responses inside a serializable transaction.

Ministry **Answer** is now restricted to questions whose status is **Awaiting Answer**. The public button, direct Administration answer context and final response insert all enforce that state. Publishing an approved ministry answer or approved follow-up updates the question status inside the same transaction as the response insert.

No database schema changes are required; safe in-place upgrade from 01.00.11.


## 01.00.13 email notification workflow

Email notifications are now split by audience and event.

- Administrators receive notification when a visitor submits a new question.
- Administrators receive notification when the original questioner submits a follow-up.
- Ministry answers do not generate an administrator notification.
- The original questioner receives an email whenever a ministry answer is published, including answers to later follow-ups.
- Registered-user notification addresses are resolved from the current DNN user account.
- Guest notification addresses are decrypted from the protected question record only when the answer notice is sent.
- Answer notices contain the answer text and a direct link back to the specific expanded Q&A conversation.
- All Q&A emails are forced to plain-text format.
- The existing **Enable email notifications** portal setting remains the master switch for both administrator and questioner notifications.

No database schema changes are required.


## 01.00.16 clean-install packaging fix

The separately placeable **Jacaranda Q&A Administration** package no longer declares `Jacaranda_QandA` as a DNN package dependency inside the same installation manifest. DNN validates package dependencies before sibling packages in the same ZIP are installed, so the dependency caused clean installations to stop with **A dependent package is not installed - Jacaranda_QandA** even though the public module appeared first in the manifest.

Both DNN modules remain bundled in the same installation ZIP, continue to share `DesktopModules/JacarandaQandA`, and use the same Q&A database. Existing server-side Administrator/Superuser checks remain unchanged. No database schema or runtime workflow changes are required.


## 01.00.16 dynamic site-title guidance

The public one-question-at-a-time guidance now uses the current DNN portal/site title instead of the hard-coded module name. For example, a portal named **Forrest Ministries Australia** displays **Forrest Ministries Australia Q&A** in the guidance text. The portal title is HTML-encoded before rendering and falls back to **This site** if no title is available. No database schema changes are required.
