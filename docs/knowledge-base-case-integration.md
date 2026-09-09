# Salesforce Knowledge on the Case Detail Page — Technical Approach

## 1. Goal

Give support agents relevant, published Knowledge articles right on the Case
record page so they can resolve cases faster, with the ability to attach an
article to the case as evidence of resolution (and, later, expose the same
articles to self-service/Experience Cloud users).

This repo implements the **custom LWC option** (Section 4.2) end-to-end.
Section 4.1 documents the **zero-code declarative option**, which should
usually be evaluated first and can be enabled in parallel with the custom
component.

---

## 2. Enable Salesforce Knowledge (one-time, declarative)

1. **Setup → Knowledge Settings**
   - Click **Enable Knowledge**. Confirm the warning (this is permanent).
   - Check **Enable Lightning Knowledge** (recommended for all new orgs —
     article types become standard-like custom objects, `<ArticleType>__kav`,
     manageable with normal object tooling, page layouts, and Lightning
     pages).
   - Configure the default **Article Number** format/starting number.
   - Set **Assignee** default and **Data Category visibility default**.
2. **Article Types** (Setup → Object Manager, or Knowledge Settings →
   "Article Types" if using Classic Knowledge):
   - Create one Article Type per content shape, e.g. `FAQ`, `How_To`,
     `Troubleshooting`. Each becomes a custom object (`FAQ__kav`) with a
     matching `FAQ__ka` "master" object.
   - Add custom fields (Rich Text `Answer__c`, `Resolution_Steps__c`,
     Picklist `Product__c`, etc.) and build a page layout per type.
3. **Data Categories** (Setup → Data Category Setup):
   - Create category groups that mirror how support triages cases, e.g.
     `Product` (Mobile App, Web App, Billing) and `Issue_Type` (How-To,
     Error, Outage).
   - Assign each article to the categories it covers; use categories to
     drive visibility (internal vs. partner vs. customer community) and to
     scope search/filtering.
4. **Permissions**:
   - Grant the **"Knowledge User"** user permission (via profile or, better,
     a dedicated permission set — see
     `force-app/main/default/permissionsets/Knowledge_Case_Agent.permissionset-meta.xml`
     in this repo) to every agent profile that should read/manage articles.
   - Configure **Data Category Group Visibility** per profile/permission set
     so agents only see categories relevant to their team; configure a
     separate, more restrictive visibility set for any Experience Cloud
     profile that will read Knowledge.
   - If Knowledge sharing is org-wide private, set up **Article sharing
     rules** or category-based sharing so the right roles/groups can view
     content.
5. **Authoring workflow**:
   - Standard lifecycle is Draft → (optional) Review/Approval Process →
     Publish → Archive. Use an **Approval Process** on the `__kav` object if
     drafts need sign-off before publishing (`KbManagement.PublishingService`
     is used internally by the Publish button/API).
   - Optionally enable **multi-language translation** (Knowledge Settings →
     languages) if the org supports non-English support channels.
6. **Validation / data quality** (optional but recommended):
   - Validation rules on the `__kav` object (e.g. require a `Summary`,
     require at least one Data Category before publish via a Flow/Apex
     trigger on `PublishStatus` transitions).

At the end of this step, agents can create, search, and publish Knowledge
articles from the **Knowledge** tab, independent of Case.

---

## 3. Enable Suggested Articles on Cases (declarative prerequisite)

Regardless of which UI option is chosen below, Case ↔ Knowledge linking uses
the standard **`CaseArticle`** junction object (`CaseId`,
`KnowledgeArticleId`, `ArticleVersionId`, plus tracking fields like
`SharedByMe`/`ArticleTitle`). No custom object is needed for the link itself.

Also confirm in **Support Settings**:
- **Enable Suggested Articles** is checked (this powers keyword matching
  between Case Subject/Description and article titles/summaries, used by
  both the standard component and as inspiration for our custom SOSL query).

---

## 4. Surface Knowledge on the Case Detail Page

### 4.1 Declarative option (evaluate first)

Salesforce ships a ready-made **Knowledge** Lightning component for Case
record pages once Lightning Knowledge is enabled:

1. Open the Case Lightning Record Page in **Lightning App Builder**
   (`Setup → Object Manager → Case → Lightning Record Pages`, or from the
   gear icon on any Case page → *Edit Page*).
2. Drag the **Knowledge** component from the component palette onto the
   page (commonly placed in a side column or as a tab next to Details).
3. Configure the component: number of articles to show, whether to allow
   **Attach**, **Email**, and **Insert into Case Feed** actions.
4. Save and **Activate** the page (org default, or assign per app/profile).

Pros: zero code, gets Einstein-assisted relevance over time, kept up to
date by Salesforce. Cons: limited customization (can't change matching
logic, can't reuse outside a standard record page/Case Feed, e.g. inside a
Flow screen or a custom Experience Cloud template region).

### 4.2 Custom LWC option (implemented in this repo)

For scenarios that need custom matching rules, a non-standard UI/branding,
or reuse outside the Case Feed (e.g. Experience Cloud, Flow screens,
embedded in Omni-Channel utility panels), this repo adds a
`caseKnowledgeArticles` Lightning Web Component:

```
force-app/main/default/classes/
  CaseKnowledgeController.cls            Apex controller (SOSL search + attach)
  CaseKnowledgeControllerTest.cls        Apex unit tests
force-app/main/default/lwc/caseKnowledgeArticles/
  caseKnowledgeArticles.js               Wire to Apex, attach handler
  caseKnowledgeArticles.html             Article list UI
  caseKnowledgeArticles.js-meta.xml      Exposed on Case record pages
  __tests__/caseKnowledgeArticles.test.js  Jest tests
force-app/main/default/permissionsets/
  Knowledge_Case_Agent.permissionset-meta.xml
```

**How it works:**

1. `CaseKnowledgeController.getSuggestedArticles(caseId)` (`@AuraEnabled
   cacheable=true`) loads the Case's `Subject`/`Description`, tokenizes them
   into significant keywords (≥4 chars, punctuation stripped), and runs a
   SOSL `FIND {token1 OR token2 …} IN ALL FIELDS RETURNING
   KnowledgeArticleVersion(...)` query restricted to `PublishStatus =
   'Online'`, ranked by relevance, limited to 5 results. It also queries
   existing `CaseArticle` links so the UI can mark articles already
   attached.
2. The LWC wires `recordId` (auto-populated by the Lightning Record Page
   context) into the Apex method, renders each article as a title + summary
   + link to the full article (`/lightning/r/Knowledge__kav/{id}/view`), and
   shows an **Attach** button for articles not yet linked.
3. Clicking **Attach** calls `CaseKnowledgeController.attachArticleToCase`,
   which inserts a `CaseArticle` record (idempotent — checks for an existing
   link first) and calls `refreshApex` to update the "Attached" badge.
4. Add the component to the Case Lightning Record Page the same way as 4.1
   step 2 (drag `Case Knowledge Articles` from the palette instead of the
   standard `Knowledge` component), or expose it on an Experience Cloud
   Case detail page, or embed it in a Flow Screen via `lightning__FlowScreen`
   (add that target in the `.js-meta.xml` if needed).

**Security model:**
- Apex enforces `WITH SECURITY_ENFORCED` on all SOQL and runs `with sharing`,
  so results always respect the running user's field-level security and
  sharing rules on `Case` and `CaseArticle`.
- Article visibility is still governed by standard Knowledge Data Category
  visibility and article sharing — the controller does not bypass it.
- Grant access via the included `Knowledge_Case_Agent` permission set
  (`KnowledgeUser` permission, class access to `CaseKnowledgeController`,
  create/read/delete on `CaseArticle`) rather than editing profiles
  directly.

---

## 5. Deployment

```bash
# Authenticate once
sf org login web --alias myOrg

# Deploy the metadata in this repo
sf project deploy start --source-dir force-app --target-org myOrg

# Assign the agent permission set
sf org assign permset --name Knowledge_Case_Agent --target-org myOrg
```

Then finish the declarative steps that cannot be captured as deployable
metadata reliably across orgs (Article Types/layouts, Data Categories, and
dragging the component onto the Lightning Record Page in App Builder) as
described in Sections 2–4.

---

## 6. Testing

- **Apex**: `CaseKnowledgeControllerTest` covers the null/guard paths for
  both methods. `Search.query` (SOSL) results depend on org data
  (Knowledge must be enabled with at least one published article to see
  non-empty matches); the tests assert the method never throws and returns
  a valid list regardless of org content, which is the safe, portable
  pattern for Knowledge-dependent Apex.
- **LWC (Jest)**: `caseKnowledgeArticles.test.js` mocks the two `@salesforce/apex`
  imports (`sfdx-lwc-jest` provides the wire adapter test utilities) and
  verifies the component renders articles and invokes `attachArticleToCase`
  on click. Run locally with:

  ```bash
  npm install
  npm run test:unit
  ```

---

## 7. Rollout & follow-ups

1. Pilot with one support team/queue; enable the `Knowledge_Case_Agent`
   permission set for that team only.
2. Monitor the standard **Knowledge Article** reports (views, "helpful"
   votes) plus Case fields like `IsClosed`/`ClosedDate` correlated with
   article attachment to gauge deflection impact.
3. Once validated, roll the permission set + Lightning Record Page change
   out org-wide.
4. Future enhancements:
   - Swap the keyword SOSL search for **Einstein Search**/**Einstein Article
     Recommendations** once licensed, for semantic relevance.
   - Expose the same `caseKnowledgeArticles` component (with a restricted
     Data Category visibility set) on the Experience Cloud **Case Detail**
     page for self-service deflection before a case is even created (e.g. on
     the Case creation form) — see "Article Suggestions" in Support
     Settings for the case-creation-time equivalent.
   - Add a scheduled Apex/Flow to flag Cases closed without any attached
     Knowledge article as candidates for new article creation ("Knowledge
     gap" report).
