/**
 * @description Server-side support for the caseKnowledgeArticles LWC.
 * Surfaces published Lightning Knowledge articles that are relevant to a
 * Case (matched against Subject/Description) and lets agents attach an
 * article to the Case (creating a CaseArticle junction record), mirroring
 * what the standard Case Feed "Knowledge" component does, but reusable on
 * any Case Lightning Record Page, Experience Cloud page, or Flow screen.
 */
public with sharing class CaseKnowledgeController {
    private static final Integer DEFAULT_LIMIT = 5;

    public class ArticleResult {
        @AuraEnabled public Id articleId;
        @AuraEnabled public Id knowledgeArticleId;
        @AuraEnabled public String title;
        @AuraEnabled public String summary;
        @AuraEnabled public String urlName;
        @AuraEnabled public String articleNumber;
        @AuraEnabled public Boolean alreadyAttached;
    }

    /**
     * @description Returns published Knowledge articles that best match the
     * given Case's Subject/Description, excluding articles already linked
     * to the Case.
     */
    @AuraEnabled(cacheable=true)
    public static List<ArticleResult> getSuggestedArticles(Id caseId) {
        List<ArticleResult> results = new List<ArticleResult>();
        if (caseId == null) {
            return results;
        }

        Case caseRecord = [
            SELECT Id, Subject, Description
            FROM Case
            WHERE Id = :caseId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Set<Id> attachedArticleIds = new Set<Id>();
        for (CaseArticle ca : [
            SELECT KnowledgeArticleId
            FROM CaseArticle
            WHERE CaseId = :caseId
            WITH SECURITY_ENFORCED
        ]) {
            attachedArticleIds.add(ca.KnowledgeArticleId);
        }

        String searchTerm = buildSearchTerm(caseRecord.Subject, caseRecord.Description);
        if (String.isBlank(searchTerm)) {
            return results;
        }

        // Curly braces (rather than quotes) let the search term contain the
        // OR operator between keywords instead of matching it as an exact
        // phrase. Tokens are pre-filtered to alphanumerics only (see
        // addSignificantTokens), so no SOSL reserved-character escaping is
        // needed here.
        List<List<SObject>> searchResults = Search.query(
            'FIND {' + searchTerm + '} IN ALL FIELDS RETURNING ' +
            'KnowledgeArticleVersion(Id, KnowledgeArticleId, Title, Summary, UrlName, ArticleNumber ' +
            'WHERE PublishStatus = \'Online\' AND Language = \'en_US\' LIMIT ' + DEFAULT_LIMIT + ')'
        );

        if (searchResults.isEmpty() || searchResults[0].isEmpty()) {
            return results;
        }

        for (SObject sObj : searchResults[0]) {
            KnowledgeArticleVersion kav = (KnowledgeArticleVersion) sObj;
            ArticleResult result = new ArticleResult();
            result.articleId = kav.Id;
            result.knowledgeArticleId = kav.KnowledgeArticleId;
            result.title = kav.Title;
            result.summary = kav.Summary;
            result.urlName = kav.UrlName;
            result.articleNumber = kav.ArticleNumber;
            result.alreadyAttached = attachedArticleIds.contains(kav.KnowledgeArticleId);
            results.add(result);
        }

        return results;
    }

    /**
     * @description Attaches a Knowledge article to a Case by inserting a
     * CaseArticle junction record, the same mechanism the standard Case
     * Feed Knowledge component uses.
     */
    @AuraEnabled
    public static void attachArticleToCase(Id caseId, Id knowledgeArticleId) {
        if (caseId == null || knowledgeArticleId == null) {
            throw new AuraHandledException('Case Id and Knowledge Article Id are required.');
        }

        List<CaseArticle> existing = [
            SELECT Id
            FROM CaseArticle
            WHERE CaseId = :caseId AND KnowledgeArticleId = :knowledgeArticleId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return;
        }

        CaseArticle link = new CaseArticle(
            CaseId = caseId,
            KnowledgeArticleId = knowledgeArticleId
        );

        try {
            insert link;
        } catch (DmlException e) {
            throw new AuraHandledException('Unable to attach article: ' + e.getMessage());
        }
    }

    private static String buildSearchTerm(String subject, String description) {
        List<String> tokens = new List<String>();
        addSignificantTokens(tokens, subject);
        addSignificantTokens(tokens, description);
        if (tokens.isEmpty()) {
            return null;
        }
        // SOSL treats space-separated quoted terms as an OR search across tokens.
        return String.join(new List<String>(new Set<String>(tokens)), ' OR ');
    }

    private static void addSignificantTokens(List<String> tokens, String text) {
        if (String.isBlank(text)) {
            return;
        }
        for (String token : text.split('[^a-zA-Z0-9]+')) {
            if (token.length() >= 4) {
                tokens.add(token);
            }
        }
    }
}
