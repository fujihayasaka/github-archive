export declare class PrimerTextAreaElement extends HTMLElement {
    #private;
    inputElement: HTMLTextAreaElement;
    characterLimitElement: HTMLElement;
    characterLimitSrElement: HTMLElement;
    connectedCallback(): void;
    disconnectedCallback(): void;
}
declare global {
    interface Window {
        PrimerTextAreaElement: typeof PrimerTextAreaElement;
    }
}
