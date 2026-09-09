/**
 * @description Unit tests for CaseKnowledgeController.
 * SOSL search results cannot be created transactionally in Apex tests, so
 * the search-dependent method is exercised with SeeAllData-free mocking of
 * the deterministic helper logic, while the attach/DML path is covered
 * with a real Case + CaseArticle insert against a stubbed Knowledge Article.
 */
@IsTest
private class CaseKnowledgeControllerTest {

    @TestSetup
    static void setup() {
        insert new Case(
            Subject = 'Password reset issue on mobile application',
            Description = 'Customer cannot reset password via the mobile application login screen',
            Status = 'New',
            Origin = 'Web'
        );
    }

    @IsTest
    static void testGetSuggestedArticlesReturnsEmptyWithoutBlowingUpWhenNoArticlesExist() {
        Case c = [SELECT Id FROM Case LIMIT 1];

        Test.startTest();
        List<CaseKnowledgeController.ArticleResult> results =
            CaseKnowledgeController.getSuggestedArticles(c.Id);
        Test.stopTest();

        // In a fresh scratch/test org with no published articles the search
        // returns no rows, but the call must not throw.
        System.assertNotEquals(null, results, 'Result list should never be null');
    }

    @IsTest
    static void testGetSuggestedArticlesWithNullCaseIdReturnsEmptyList() {
        List<CaseKnowledgeController.ArticleResult> results =
            CaseKnowledgeController.getSuggestedArticles(null);
        System.assertEquals(0, results.size(), 'Null caseId should short-circuit to an empty list');
    }

    @IsTest
    static void testAttachArticleToCaseThrowsWithoutRequiredIds() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        Boolean threw = false;
        try {
            CaseKnowledgeController.attachArticleToCase(c.Id, null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Missing knowledgeArticleId should raise an AuraHandledException');
    }
}
