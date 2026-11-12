import { IncludeFragmentElement } from '@github/include-fragment-element';
export declare class TreeViewIncludeFragmentElement extends IncludeFragmentElement {
    request(): Request;
}
declare global {
    interface Window {
        TreeViewIncludeFragmentElement: typeof TreeViewIncludeFragmentElement;
    }
}
