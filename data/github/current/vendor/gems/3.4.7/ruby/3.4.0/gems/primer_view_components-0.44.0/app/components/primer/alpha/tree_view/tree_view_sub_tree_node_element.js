var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __classPrivateFieldGet = (this && this.__classPrivateFieldGet) || function (receiver, state, kind, f) {
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a getter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot read private member from an object whose class did not declare it");
    return kind === "m" ? f : kind === "a" ? f.call(receiver) : f ? f.value : state.get(receiver);
};
var __classPrivateFieldSet = (this && this.__classPrivateFieldSet) || function (receiver, state, value, kind, f) {
    if (kind === "m") throw new TypeError("Private method is not writable");
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a setter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot write private member to an object whose class did not declare it");
    return (kind === "a" ? f.call(receiver, value) : f ? f.value = value : state.set(receiver, value)), value;
};
var _TreeViewSubTreeNodeElement_instances, _TreeViewSubTreeNodeElement_expanded, _TreeViewSubTreeNodeElement_loadingState, _TreeViewSubTreeNodeElement_abortController, _TreeViewSubTreeNodeElement_activeElementIsLoader, _TreeViewSubTreeNodeElement_handleToggleEvent, _TreeViewSubTreeNodeElement_handleIncludeFragmentEvent, _TreeViewSubTreeNodeElement_handleRetryButtonEvent, _TreeViewSubTreeNodeElement_handleKeyboardEvent, _TreeViewSubTreeNodeElement_handleCheckboxEvent, _TreeViewSubTreeNodeElement_update, _TreeViewSubTreeNodeElement_checkboxElement_get;
import { controller, target } from '@github/catalyst';
import { observeMutationsUntilConditionMet } from '../../utils';
let TreeViewSubTreeNodeElement = class TreeViewSubTreeNodeElement extends HTMLElement {
    constructor() {
        super(...arguments);
        _TreeViewSubTreeNodeElement_instances.add(this);
        _TreeViewSubTreeNodeElement_expanded.set(this, null);
        _TreeViewSubTreeNodeElement_loadingState.set(this, 'success');
        _TreeViewSubTreeNodeElement_abortController.set(this, void 0);
        _TreeViewSubTreeNodeElement_activeElementIsLoader.set(this, false);
    }
    connectedCallback() {
        observeMutationsUntilConditionMet(this, () => Boolean(this.node) && Boolean(this.subTree), () => {
            __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "m", _TreeViewSubTreeNodeElement_update).call(this);
        });
        const { signal } = (__classPrivateFieldSet(this, _TreeViewSubTreeNodeElement_abortController, new AbortController(), "f"));
        this.addEventListener('click', this, { signal });
        this.addEventListener('keydown', this, { signal });
        observeMutationsUntilConditionMet(this, () => Boolean(this.includeFragment), () => {
            this.includeFragment.addEventListener('loadstart', this, { signal });
            this.includeFragment.addEventListener('error', this, { signal });
            this.includeFragment.addEventListener('include-fragment-replace', this, { signal });
            this.includeFragment.addEventListener('include-fragment-replaced', (e) => {
                __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "m", _TreeViewSubTreeNodeElement_handleIncludeFragmentEvent).call(this, e);
            }, { signal });
        });
        observeMutationsUntilConditionMet(this, () => Boolean(this.retryButton), () => {
            this.retryButton.addEventListener('click', event => {
                __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "m", _TreeViewSubTreeNodeElement_handleRetryButtonEvent).call(this, event);
            }, { signal });
        });
        const checkedMutationObserver = new MutationObserver(() => {
            if (this.selectStrategy !== 'mixed_descendants')
                return;
            let checkType = 'unknown';
            for (const node of this.eachDirectDescendantNode()) {
                switch (`${checkType} ${node.getAttribute('aria-checked') || 'false'}`) {
                    case 'unknown mixed':
                    case 'false mixed':
                    case 'true mixed':
                    case 'false true':
                    case 'true false':
                        checkType = 'mixed';
                        break;
                    case 'unknown false':
                        checkType = 'false';
                        break;
                    case 'unknown true':
                        checkType = 'true';
                }
            }
            if (checkType !== 'unknown' && this.node?.getAttribute('aria-checked') !== checkType) {
                this.node?.setAttribute('aria-checked', checkType);
            }
        });
        checkedMutationObserver.observe(this, {
            childList: true,
            subtree: true,
            attributeFilter: ['aria-checked'],
        });
    }
    get expanded() {
        if (__classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_expanded, "f") === null) {
            __classPrivateFieldSet(this, _TreeViewSubTreeNodeElement_expanded, this.node.getAttribute('aria-expanded') === 'true', "f");
        }
        return __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_expanded, "f");
    }
    set expanded(newValue) {
        __classPrivateFieldSet(this, _TreeViewSubTreeNodeElement_expanded, newValue, "f");
        __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "m", _TreeViewSubTreeNodeElement_update).call(this);
    }
    get loadingState() {
        return __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_loadingState, "f");
    }
    set loadingState(newState) {
        __classPrivateFieldSet(this, _TreeViewSubTreeNodeElement_loadingState, newState, "f");
        __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "m", _TreeViewSubTreeNodeElement_update).call(this);
    }
    get selectStrategy() {
        return (this.node.getAttribute('data-select-strategy') || 'descendants');
    }
    disconnectedCallback() {
        __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_abortController, "f").abort();
    }
    handleEvent(event) {
        if (event.target === this.toggleButton) {
            __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "m", _TreeViewSubTreeNodeElement_handleToggleEvent).call(this, event);
        }
        else if (event.target === this.includeFragment) {
            __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "m", _TreeViewSubTreeNodeElement_handleIncludeFragmentEvent).call(this, event);
        }
        else if (event instanceof KeyboardEvent) {
            __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "m", _TreeViewSubTreeNodeElement_handleKeyboardEvent).call(this, event);
        }
        else if (event.target.closest('[role=treeitem]') === this.node &&
            event.type === 'click' &&
            __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "a", _TreeViewSubTreeNodeElement_checkboxElement_get)) {
            __classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "m", _TreeViewSubTreeNodeElement_handleCheckboxEvent).call(this, event);
        }
    }
    expand() {
        const alreadyExpanded = this.expanded;
        this.expanded = true;
        if (!alreadyExpanded && this.treeView) {
            this.treeView.dispatchEvent(new CustomEvent('treeViewNodeExpanded', {
                bubbles: true,
                detail: this.treeView?.infoFromNode(this.node),
            }));
        }
    }
    collapse() {
        const alreadyCollapsed = !this.expanded;
        this.expanded = false;
        if (!alreadyCollapsed && this.treeView) {
            // Prevent issue where currently focusable node is stuck inside a collapsed
            // sub-tree and no node in the entire tree can be focused
            const previousNode = this.subTree.querySelector("[tabindex='0']");
            previousNode?.setAttribute('tabindex', '-1');
            this.node.setAttribute('tabindex', '0');
            this.treeView.dispatchEvent(new CustomEvent('treeViewNodeCollapsed', {
                bubbles: true,
                detail: this.treeView?.infoFromNode(this.node),
            }));
        }
    }
    toggle() {
        if (this.expanded) {
            this.collapse();
        }
        else {
            this.expand();
        }
    }
    get nodes() {
        return this.querySelectorAll(':scope > [role=treeitem]');
    }
    *eachDirectDescendantNode() {
        for (const leaf of this.subTree.querySelectorAll(':scope > li > .TreeViewItemContainer > [role=treeitem]')) {
            yield leaf;
        }
        for (const subTree of this.subTree.querySelectorAll(':scope > tree-view-sub-tree-node > li > .TreeViewItemContainer > [role=treeitem]')) {
            yield subTree;
        }
    }
    *eachDescendantNode() {
        for (const node of this.subTree.querySelectorAll('[role=treeitem]')) {
            yield node;
        }
    }
    *eachAncestorSubTreeNode() {
        if (!this.treeView)
            return;
        // eslint-disable-next-line @typescript-eslint/no-this-alias
        let current = this;
        while (current && this.treeView.contains(current)) {
            yield current;
            current = current.parentElement?.closest('tree-view-sub-tree-node');
        }
    }
    get isEmpty() {
        return this.nodes.length === 0;
    }
    get treeView() {
        return this.closest('tree-view');
    }
    toggleChecked() {
        const checkValue = this.treeView?.getNodeCheckedValue(this.node) || 'false';
        const newCheckValue = checkValue === 'false' ? 'true' : 'false';
        const nodeInfos = [];
        const rootInfo = this.treeView?.infoFromNode(this.node, newCheckValue);
        if (rootInfo)
            nodeInfos.push(rootInfo);
        if (this.selectStrategy === 'descendants' || this.selectStrategy === 'mixed_descendants') {
            for (const node of this.eachDescendantNode()) {
                const info = this.treeView?.infoFromNode(node, newCheckValue);
                if (info)
                    nodeInfos.push(info);
            }
        }
        const checkSuccess = this.dispatchEvent(new CustomEvent('treeViewBeforeNodeChecked', {
            bubbles: true,
            cancelable: true,
            detail: nodeInfos,
        }));
        if (!checkSuccess)
            return;
        for (const nodeInfo of nodeInfos) {
            nodeInfo.node.setAttribute('aria-checked', newCheckValue);
        }
        this.dispatchEvent(new CustomEvent('treeViewNodeChecked', {
            bubbles: true,
            cancelable: true,
            detail: nodeInfos,
        }));
    }
};
_TreeViewSubTreeNodeElement_expanded = new WeakMap();
_TreeViewSubTreeNodeElement_loadingState = new WeakMap();
_TreeViewSubTreeNodeElement_abortController = new WeakMap();
_TreeViewSubTreeNodeElement_activeElementIsLoader = new WeakMap();
_TreeViewSubTreeNodeElement_instances = new WeakSet();
_TreeViewSubTreeNodeElement_handleToggleEvent = function _TreeViewSubTreeNodeElement_handleToggleEvent(event) {
    if (event.type === 'click') {
        this.toggle();
        // eslint-disable-next-line no-restricted-syntax
        event.stopPropagation();
    }
};
_TreeViewSubTreeNodeElement_handleIncludeFragmentEvent = function _TreeViewSubTreeNodeElement_handleIncludeFragmentEvent(event) {
    switch (event.type) {
        // the request has started
        case 'loadstart':
            this.loadingState = 'loading';
            break;
        // the request failed
        case 'error':
            this.loadingState = 'error';
            break;
        // request succeeded but element has not yet been replaced
        case 'include-fragment-replace':
            __classPrivateFieldSet(this, _TreeViewSubTreeNodeElement_activeElementIsLoader, document.activeElement === this.loadingIndicator.closest('[role=treeitem]'), "f");
            this.loadingState = 'success';
            break;
        case 'include-fragment-replaced':
            // Make sure to expand the new sub-tree, otherwise it looks like nothing happened. This prevents
            // having to remember to pass `SubTree.new(expanded: true)` in the controller.
            this.expanded = true;
            if (__classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_activeElementIsLoader, "f")) {
                const firstItem = this.querySelector('[role=group] > :first-child');
                if (!firstItem)
                    return;
                const content = firstItem.querySelector('[role=treeitem]');
                if (!content)
                    return;
                content.focus();
            }
            __classPrivateFieldSet(this, _TreeViewSubTreeNodeElement_activeElementIsLoader, false, "f");
            break;
    }
};
_TreeViewSubTreeNodeElement_handleRetryButtonEvent = function _TreeViewSubTreeNodeElement_handleRetryButtonEvent(event) {
    if (event.type === 'click') {
        this.loadingState = 'loading';
        this.includeFragment.refetch();
    }
};
_TreeViewSubTreeNodeElement_handleKeyboardEvent = function _TreeViewSubTreeNodeElement_handleKeyboardEvent(event) {
    const node = event.target.closest('[role=treeitem]');
    if (!node || this.treeView?.getNodeType(node) !== 'sub-tree') {
        return;
    }
    switch (event.key) {
        case 'Enter':
            if (this.treeView?.getNodeDisabledValue(node)) {
                event.preventDefault();
                break;
            }
            // eslint-disable-next-line no-restricted-syntax
            event.stopPropagation();
            if (__classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "a", _TreeViewSubTreeNodeElement_checkboxElement_get)) {
                this.toggleChecked();
            }
            else if (!this.treeView?.nodeHasNativeAction(node)) {
                // toggle only if this node isn't eg. an anchor or button
                this.toggle();
            }
            break;
        case 'ArrowRight':
            // eslint-disable-next-line no-restricted-syntax
            event.stopPropagation();
            this.expand();
            break;
        case 'ArrowLeft':
            // eslint-disable-next-line no-restricted-syntax
            event.stopPropagation();
            this.collapse();
            break;
        case ' ':
            if (this.treeView?.getNodeDisabledValue(node)) {
                event.preventDefault();
                break;
            }
            if (__classPrivateFieldGet(this, _TreeViewSubTreeNodeElement_instances, "a", _TreeViewSubTreeNodeElement_checkboxElement_get)) {
                // eslint-disable-next-line no-restricted-syntax
                event.stopPropagation();
                event.preventDefault();
                this.toggleChecked();
            }
            else {
                if (node instanceof HTMLAnchorElement) {
                    // simulate click on space for anchors (buttons already handle this natively)
                    node.click();
                }
                else if (!this.treeView?.nodeHasNativeAction(node)) {
                    this.toggle();
                }
            }
            break;
    }
};
_TreeViewSubTreeNodeElement_handleCheckboxEvent = function _TreeViewSubTreeNodeElement_handleCheckboxEvent(event) {
    if (this.treeView?.getNodeDisabledValue(this.node)) {
        event.preventDefault();
        return;
    }
    if (event.type !== 'click')
        return;
    this.toggleChecked();
    // prevent receiving this event twice
    // eslint-disable-next-line no-restricted-syntax
    event.stopPropagation();
};
_TreeViewSubTreeNodeElement_update = function _TreeViewSubTreeNodeElement_update() {
    if (this.expanded) {
        if (this.subTree)
            this.subTree.hidden = false;
        this.node.setAttribute('aria-expanded', 'true');
        this.treeView?.expandAncestorsForNode(this);
        if (this.iconPair) {
            this.iconPair.showExpanded();
        }
        if (this.expandedToggleIcon && this.collapsedToggleIcon) {
            this.expandedToggleIcon.removeAttribute('hidden');
            this.collapsedToggleIcon.setAttribute('hidden', 'hidden');
        }
    }
    else {
        if (this.subTree)
            this.subTree.hidden = true;
        this.node.setAttribute('aria-expanded', 'false');
        if (this.iconPair) {
            this.iconPair.showCollapsed();
        }
        if (this.expandedToggleIcon && this.collapsedToggleIcon) {
            this.expandedToggleIcon.setAttribute('hidden', 'hidden');
            this.collapsedToggleIcon.removeAttribute('hidden');
        }
    }
    switch (this.loadingState) {
        case 'loading':
            if (this.loadingFailureMessage)
                this.loadingFailureMessage.hidden = true;
            if (this.loadingIndicator)
                this.loadingIndicator.hidden = false;
            break;
        case 'error':
            if (this.loadingIndicator)
                this.loadingIndicator.hidden = true;
            if (this.loadingFailureMessage)
                this.loadingFailureMessage.hidden = false;
            break;
        // success/init case
        default:
            if (this.loadingIndicator)
                this.loadingIndicator.hidden = true;
            if (this.loadingFailureMessage)
                this.loadingFailureMessage.hidden = true;
    }
};
_TreeViewSubTreeNodeElement_checkboxElement_get = function _TreeViewSubTreeNodeElement_checkboxElement_get() {
    return this.querySelector('.TreeViewItemCheckbox');
};
__decorate([
    target
], TreeViewSubTreeNodeElement.prototype, "node", void 0);
__decorate([
    target
], TreeViewSubTreeNodeElement.prototype, "subTree", void 0);
__decorate([
    target
], TreeViewSubTreeNodeElement.prototype, "iconPair", void 0);
__decorate([
    target
], TreeViewSubTreeNodeElement.prototype, "toggleButton", void 0);
__decorate([
    target
], TreeViewSubTreeNodeElement.prototype, "expandedToggleIcon", void 0);
__decorate([
    target
], TreeViewSubTreeNodeElement.prototype, "collapsedToggleIcon", void 0);
__decorate([
    target
], TreeViewSubTreeNodeElement.prototype, "includeFragment", void 0);
__decorate([
    target
], TreeViewSubTreeNodeElement.prototype, "loadingIndicator", void 0);
__decorate([
    target
], TreeViewSubTreeNodeElement.prototype, "loadingFailureMessage", void 0);
__decorate([
    target
], TreeViewSubTreeNodeElement.prototype, "retryButton", void 0);
TreeViewSubTreeNodeElement = __decorate([
    controller
], TreeViewSubTreeNodeElement);
export { TreeViewSubTreeNodeElement };
if (!window.customElements.get('tree-view-sub-tree-node')) {
    window.TreeViewSubTreeNodeElement = TreeViewSubTreeNodeElement;
    window.customElements.define('tree-view-sub-tree-node', TreeViewSubTreeNodeElement);
}
