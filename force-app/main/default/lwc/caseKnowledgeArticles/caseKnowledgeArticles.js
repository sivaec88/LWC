import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSuggestedArticles from '@salesforce/apex/CaseKnowledgeController.getSuggestedArticles';
import attachArticleToCase from '@salesforce/apex/CaseKnowledgeController.attachArticleToCase';

export default class CaseKnowledgeArticles extends LightningElement {
    /** Case record id, auto-populated by the Lightning Record Page context. */
    @api recordId;

    articles = [];
    error;
    isLoading = true;
    wiredResult;

    @wire(getSuggestedArticles, { caseId: '$recordId' })
    wiredArticles(value) {
        this.wiredResult = value;
        const { data, error } = value;
        this.isLoading = false;
        if (data) {
            this.articles = data.map((article) => ({
                ...article,
                articleUrl: `/lightning/r/Knowledge__kav/${article.knowledgeArticleId}/view`
            }));
            this.error = undefined;
        } else if (error) {
            this.error = this.reduceError(error);
            this.articles = [];
        }
    }

    get hasArticles() {
        return this.articles && this.articles.length > 0;
    }

    get showEmptyState() {
        return !this.isLoading && !this.error && !this.hasArticles;
    }

    async handleAttach(event) {
        const knowledgeArticleId = event.currentTarget.dataset.articleId;
        try {
            await attachArticleToCase({ caseId: this.recordId, knowledgeArticleId });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Article attached',
                    message: 'The Knowledge article was linked to this case.',
                    variant: 'success'
                })
            );
            await refreshApex(this.wiredResult);
        } catch (e) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to attach article',
                    message: this.reduceError(e),
                    variant: 'error'
                })
            );
        }
    }

    reduceError(error) {
        return (
            error?.body?.message ||
            error?.message ||
            'Unknown error while contacting Salesforce Knowledge.'
        );
    }
}
