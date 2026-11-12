var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { controller } from '@github/catalyst';
import { IncludeFragmentElement } from '@github/include-fragment-element';
let TreeViewIncludeFragmentElement = class TreeViewIncludeFragmentElement extends IncludeFragmentElement {
    request() {
        const originalRequest = super.request();
        const url = new URL(originalRequest.url);
        url.searchParams.set('path', this.getAttribute('data-path') || '');
        return new Request(url, {
            method: originalRequest.method,
            headers: originalRequest.headers,
            credentials: originalRequest.credentials,
        });
    }
};
TreeViewIncludeFragmentElement = __decorate([
    controller
], TreeViewIncludeFragmentElement);
export { TreeViewIncludeFragmentElement };
if (!window.customElements.get('tree-view-include-fragment')) {
    window.TreeViewIncludeFragmentElement = TreeViewIncludeFragmentElement;
    window.customElements.define('tree-view-include-fragment', TreeViewIncludeFragmentElement);
}
