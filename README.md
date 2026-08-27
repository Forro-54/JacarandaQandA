# Jacaranda Q&A

Jacaranda Q&A is an independent DNN 10 WebForms module for moderated theological question-and-answer ministry.

## Version

01.00.09 — Inline follow-up response placement.

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
