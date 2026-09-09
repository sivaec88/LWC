import { createElement } from 'lwc';
import { createApexTestWireAdapter } from '@salesforce/wire-service-jest-util';
import CaseKnowledgeArticles from 'c/caseKnowledgeArticles';
import getSuggestedArticles from '@salesforce/apex/CaseKnowledgeController.getSuggestedArticles';

const mockAttach = jest.fn();

jest.mock(
    '@salesforce/apex/CaseKnowledgeController.getSuggestedArticles',
    () => {
        // eslint-disable-next-line global-require
        const { createApexTestWireAdapter: mockCreateApexTestWireAdapter } = require('@salesforce/wire-service-jest-util');
        return { default: mockCreateApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/CaseKnowledgeController.attachArticleToCase',
    () => ({ default: (...args) => mockAttach(...args) }),
    { virtual: true }
);

const ARTICLES = [
    {
        articleId: 'aVersion001',
        knowledgeArticleId: 'kA0001',
        title: 'How to reset your password',
        summary: 'Step by step password reset guide',
        urlName: 'how-to-reset-your-password',
        articleNumber: '000001',
        alreadyAttached: false
    }
];

function flushPromises() {
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-case-knowledge-articles', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders suggested articles returned from Apex', async () => {
        const element = createElement('c-case-knowledge-articles', {
            is: CaseKnowledgeArticles
        });
        element.recordId = '500000000000001';
        document.body.appendChild(element);

        getSuggestedArticles.emit(ARTICLES);
        await flushPromises();

        const links = element.shadowRoot.querySelectorAll('a');
        expect(links.length).toBe(1);
        expect(links[0].textContent.trim()).toBe(ARTICLES[0].title);

        const attachButtons = element.shadowRoot.querySelectorAll('lightning-button');
        expect(attachButtons.length).toBe(1);
    });

    it('shows the empty state when no articles are returned', async () => {
        const element = createElement('c-case-knowledge-articles', {
            is: CaseKnowledgeArticles
        });
        element.recordId = '500000000000001';
        document.body.appendChild(element);

        getSuggestedArticles.emit([]);
        await flushPromises();

        const empty = element.shadowRoot.querySelector('p');
        expect(empty).not.toBeNull();
        expect(empty.textContent).toContain('No matching articles');
    });

    it('marks already-attached articles with a badge instead of an Attach button', async () => {
        const element = createElement('c-case-knowledge-articles', {
            is: CaseKnowledgeArticles
        });
        element.recordId = '500000000000001';
        document.body.appendChild(element);

        getSuggestedArticles.emit([{ ...ARTICLES[0], alreadyAttached: true }]);
        await flushPromises();

        expect(element.shadowRoot.querySelector('lightning-badge')).not.toBeNull();
        expect(element.shadowRoot.querySelector('lightning-button')).toBeNull();
    });

    it('calls attachArticleToCase when the Attach button is clicked', async () => {
        mockAttach.mockResolvedValue(undefined);

        const element = createElement('c-case-knowledge-articles', {
            is: CaseKnowledgeArticles
        });
        element.recordId = '500000000000001';
        document.body.appendChild(element);

        getSuggestedArticles.emit(ARTICLES);
        await flushPromises();

        const button = element.shadowRoot.querySelector('lightning-button');
        expect(button).not.toBeNull();
        button.click();
        await flushPromises();

        expect(mockAttach).toHaveBeenCalledWith({
            caseId: '500000000000001',
            knowledgeArticleId: 'kA0001'
        });
    });

    it('surfaces an error message when attachArticleToCase fails', async () => {
        mockAttach.mockRejectedValue({ body: { message: 'Duplicate link' } });

        const element = createElement('c-case-knowledge-articles', {
            is: CaseKnowledgeArticles
        });
        element.recordId = '500000000000001';
        const toastHandler = jest.fn();
        element.addEventListener('lightning__showtoast', toastHandler);
        document.body.appendChild(element);

        getSuggestedArticles.emit(ARTICLES);
        await flushPromises();

        element.shadowRoot.querySelector('lightning-button').click();
        await flushPromises();

        expect(toastHandler).toHaveBeenCalled();
        expect(toastHandler.mock.calls[0][0].detail.variant).toBe('error');
    });
});
