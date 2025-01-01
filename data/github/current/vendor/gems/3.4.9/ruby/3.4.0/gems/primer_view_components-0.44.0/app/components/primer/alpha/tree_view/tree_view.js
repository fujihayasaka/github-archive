var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __classPrivateFieldSet = (this && this.__classPrivateFieldSet) || function (receiver, state, value, kind, f) {
    if (kind === "m") throw new TypeError("Private method is not writable");
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a setter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot write private member to an object whose class did not declare it");
    return (kind === "a" ? f.call(receiver, value) : f ? f.value = value : state.set(receiver, value)), value;
};
var __classPrivateFieldGet = (this && this.__classPrivateFieldGet) || function (receiver, state, kind, f) {
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a getter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot read private member from an object whose class did not declare it");
    return kind === "m" ? f : kind === "a" ? f.call(receiver) : f ? f.value : state.get(receiver);
};
var _TreeViewElement_instances, _TreeViewElement_abortController, _TreeViewElement_autoExpandFrom, _TreeViewElement_eventIsActivation, _TreeViewElement_nodeForEvent, _TreeViewElement_handleNodeEvent, _TreeViewElement_eventIsCheckboxToggle, _TreeViewElement_handleCheckboxToggle, _TreeViewElement_handleNodeActivated, _TreeViewElement_handleNodeFocused, _TreeViewElement_handleNodeKeyboardEvent;
import { controller, target } from '@github/catalyst';
import { useRovingTabIndex } from './tree_view_roving_tab_index';
let TreeViewElement = class TreeViewElement extends HTMLElement {
    constructor() {
        super(...arguments);
        _TreeViewElement_instances.add(this);
        _TreeViewElement_abortController.set(this, void 0);
    }
    connectedCallback() {
        const { signal } = (__classPrivateFieldSet(this, _TreeViewElement_abortController, new AbortController(), "f"));
        this.addEventListener('click', this, { signal });
        this.addEventListener('focusin', this, { signal });
        this.addEventListener('keydown', this, { signal });
        useRovingTabIndex(this);
        // catch-all for any straggler nodes that aren't available when connectedCallback runs
        new MutationObserver(mutations => {
            for (const mutation of mutations) {
                for (const addedNode of mutation.addedNodes) {
                    if (!(addedNode instanceof HTMLElement))
                        continue;
                    if (addedNode.querySelector('[aria-expanded=true]')) {
                        __classPrivateFieldGet(this, _TreeViewElement_instances, "m", _TreeViewElement_autoExpandFrom).call(this, addedNode);
                    }
                }
            }
        }).observe(this, { childList: true, subtree: true });
        const updateInputsObserver = new MutationObserver(mutations => {
            if (!this.formInputContainer)
                return;
            // There is another MutationObserver in TreeViewSubTreeNodeElement that manages checking/unchecking
            // nodes based on the component's select strategy. These two observers can conflict and cause infinite
            // looping, so we make sure something actually changed before computing inputs again.
            const somethingChanged = mutations.some(m => {
                if (!(m.target instanceof HTMLElement))
                    return false;
                return m.target.getAttribute('aria-checked') !== m.oldValue;
            });
            if (!somethingChanged)
                return;
            const newInputs = [];
            for (const node of this.querySelectorAll('[role=treeitem][aria-checked=true]')) {
                const newInput = this.formInputPrototype.cloneNode();
                newInput.removeAttribute('data-target');
                newInput.removeAttribute('form');
                const payload = {
                    path: this.getNodePath(node),
                };
                const inputValue = this.getFormInputValueForNode(node);
                if (inputValue)
                    payload.value = inputValue;
                newInput.value = JSON.stringify(payload);
                newInputs.push(newInput);
            }
            this.formInputContainer.replaceChildren(...newInputs);
        });
        updateInputsObserver.observe(this, {
            childList: true,
            subtree: true,
            attributeFilter: ['aria-checked'],
        });
        // eslint-disable-next-line github/no-then -- We don't want to wait for this to resolve, just get on with it
        customElements.whenDefined('tree-view-sub-tree-node').then(() => {
            // depends on TreeViewSubTreeNodeElement#eachAncestorSubTreeNode, which may not be defined yet
            __classPrivateFieldGet(this, _TreeViewElement_instances, "m", _TreeViewElement_autoExpandFrom).call(this, this);
        });
    }
    disconnectedCallback() {
        __classPrivateFieldGet(this, _TreeViewElement_abortController, "f").abort();
    }
    handleEvent(event) {
        const node = __classPrivateFieldGet(this, _TreeViewElement_instances, "m", _TreeViewElement_nodeForEvent).call(this, event);
        if (node) {
            __classPrivateFieldGet(this, _TreeViewElement_instances, "m", _TreeViewElement_handleNodeEvent).call(this, node, event);
        }
    }
    getFormInputValueForNode(node) {
        return node.getAttribute('data-value');
    }
    getNodePath(node) {
        const rawPath = node.getAttribute('data-path');
        if (rawPath) {
            return JSON.parse(rawPath);
        }
        return [];
    }
    getNodeType(node) {
        return node.getAttribute('data-node-type');
    }
    markCurrentAtPath(path) {
        const pathStr = JSON.stringify(path);
        const nodeToMark = this.querySelector(`[data-path="${CSS.escape(pathStr)}"`);
        if (!nodeToMark)
            return;
        this.currentNode?.setAttribute('aria-current', 'false');
        nodeToMark.setAttribute('aria-current', 'true');
    }
    get currentNode() {
        return this.querySelector('[aria-current=true]');
    }
    expandAtPath(path) {
        const node = this.subTreeAtPath(path);
        if (!node)
            return;
        node.expand();
    }
    collapseAtPath(path) {
        const node = this.subTreeAtPath(path);
        if (!node)
            return;
        node.collapse();
    }
    toggleAtPath(path) {
        const node = this.subTreeAtPath(path);
        if (!node)
            return;
        node.toggle();
    }
    checkAtPath(path) {
        const node = this.nodeAtPath(path);
        if (!node)
            return;
        this.setNodeCheckedValue(node, 'true');
    }
    uncheckAtPath(path) {
        const node = this.nodeAtPath(path);
        if (!node)
            return;
        this.setNodeCheckedValue(node, 'false');
    }
    toggleCheckedAtPath(path) {
        const node = this.nodeAtPath(path);
        if (!node)
            return;
        if (this.getNodeType(node) === 'leaf') {
            if (this.getNodeCheckedValue(node) === 'true') {
                this.uncheckAtPath(path);
            }
            else {
                this.checkAtPath(path);
            }
        }
    }
    checkedValueAtPath(path) {
        const node = this.nodeAtPath(path);
        if (!node)
            return 'false';
        return this.getNodeCheckedValue(node);
    }
    disabledValueAtPath(path) {
        const node = this.nodeAtPath(path);
        if (!node)
            return false;
        return this.getNodeDisabledValue(node);
    }
    nodeAtPath(path, selector) {
        const pathStr = JSON.stringify(path);
        return this.querySelector(`${selector || ''}[data-path="${CSS.escape(pathStr)}"]`);
    }
    subTreeAtPath(path) {
        const node = this.nodeAtPath(path, '[data-node-type=sub-tree]');
        if (!node)
            return null;
        return node.closest('tree-view-sub-tree-node');
    }
    leafAtPath(path) {
        return this.nodeAtPath(path, '[data-node-type=leaf]');
    }
    setNodeCheckedValue(node, value) {
        node.setAttribute('aria-checked', value.toString());
    }
    getNodeCheckedValue(node) {
        return (node.getAttribute('aria-checked') || 'false');
    }
    getNodeDisabledValue(node) {
        return node.getAttribute('aria-disabled') === 'true';
    }
    setNodeDisabledValue(node, disabled) {
        if (disabled) {
            node.setAttribute('aria-disabled', 'true');
        }
        else {
            node.removeAttribute('aria-disabled');
        }
    }
    nodeHasCheckBox(node) {
        return node.querySelector('.TreeViewItemCheckbox') !== null;
    }
    nodeHasNativeAction(node) {
        return node instanceof HTMLAnchorElement || node instanceof HTMLButtonElement;
    }
    expandAncestorsForNode(node) {
        const subTreeNode = node.closest('tree-view-sub-tree-node');
        if (!subTreeNode)
            return;
        for (const ancestor of subTreeNode.eachAncestorSubTreeNode()) {
            if (!ancestor.expanded) {
                ancestor.expand();
            }
        }
    }
    // PRIVATE API METHOD
    //
    // This would normally be marked private, but it's called by TreeViewSubTreeNodes
    // and thus must be public.
    infoFromNode(node, newCheckedValue) {
        const type = this.getNodeType(node);
        if (!type)
            return null;
        const checkedValue = this.getNodeCheckedValue(node);
        return {
            node,
            type,
            path: this.getNodePath(node),
            checkedValue: newCheckedValue || checkedValue,
            previousCheckedValue: checkedValue,
        };
    }
};
_TreeViewElement_abortController = new WeakMap();
_TreeViewElement_instances = new WeakSet();
_TreeViewElement_autoExpandFrom = function _TreeViewElement_autoExpandFrom(root) {
    for (const element of root.querySelectorAll('[aria-expanded=true]')) {
        this.expandAncestorsForNode(element);
    }
};
_TreeViewElement_eventIsActivation = function _TreeViewElement_eventIsActivation(event) {
    return event.type === 'click';
};
_TreeViewElement_nodeForEvent = function _TreeViewElement_nodeForEvent(event) {
    const eventTarget = event.target;
    const node = eventTarget.closest('[role=treeitem]');
    if (!node)
        return null;
    if (eventTarget.closest('.TreeViewItemToggle'))
        return null;
    if (eventTarget.closest('.TreeViewItemLeadingAction'))
        return null;
    return node;
};
_TreeViewElement_handleNodeEvent = function _TreeViewElement_handleNodeEvent(node, event) {
    if (__classPrivateFieldGet(this, _TreeViewElement_instances, "m", _TreeViewElement_eventIsCheckboxToggle).call(this, event, node)) {
        __classPrivateFieldGet(this, _TreeViewElement_instances, "m", _TreeViewElement_handleCheckboxToggle).call(this, event, node);
    }
    else if (__classPrivateFieldGet(this, _TreeViewElement_instances, "m", _TreeViewElement_eventIsActivation).call(this, event)) {
        __classPrivateFieldGet(this, _TreeViewElement_instances, "m", _TreeViewElement_handleNodeActivated).call(this, event, node);
    }
    else if (event.type === 'focusin') {
        __classPrivateFieldGet(this, _TreeViewElement_instances, "m", _TreeViewElement_handleNodeFocused).call(this, node);
    }
    else if (event instanceof KeyboardEvent) {
        __classPrivateFieldGet(this, _TreeViewElement_instances, "m", _TreeViewElement_handleNodeKeyboardEvent).call(this, event, node);
    }
};
_TreeViewElement_eventIsCheckboxToggle = function _TreeViewElement_eventIsCheckboxToggle(event, node) {
    return event.type === 'click' && this.nodeHasCheckBox(node);
};
_TreeViewElement_handleCheckboxToggle = function _TreeViewElement_handleCheckboxToggle(event, node) {
    if (this.getNodeDisabledValue(node)) {
        event.preventDefault();
        return;
    }
    // only handle checking of leaf nodes, see TreeViewSubTreeNodeElement for the code that
    // handles checking sub tree items.
    const type = this.getNodeType(node);
    if (type !== 'leaf')
        return;
    if (this.getNodeCheckedValue(node) === 'true') {
        this.setNodeCheckedValue(node, 'false');
    }
    else {
        this.setNodeCheckedValue(node, 'true');
    }
};
_TreeViewElement_handleNodeActivated = function _TreeViewElement_handleNodeActivated(event, node) {
    if (this.getNodeDisabledValue(node)) {
        event.preventDefault();
        return;
    }
    // do not emit activation events for buttons and anchors, since it is assumed any activation
    // behavior for these element types is user- or browser-defined
    if (!(node instanceof HTMLDivElement))
        return;
    const path = this.getNodePath(node);
    const activationSuccess = this.dispatchEvent(new CustomEvent('treeViewBeforeNodeActivated', {
        bubbles: true,
        cancelable: true,
        detail: this.infoFromNode(node),
    }));
    if (!activationSuccess)
        return;
    // navigate or trigger button, don't toggle
    if (!this.nodeHasNativeAction(node)) {
        this.toggleAtPath(path);
    }
    this.dispatchEvent(new CustomEvent('treeViewNodeActivated', {
        bubbles: true,
        detail: this.infoFromNode(node),
    }));
};
_TreeViewElement_handleNodeFocused = function _TreeViewElement_handleNodeFocused(node) {
    const previousNode = this.querySelector('[aria-selected=true]');
    previousNode?.setAttribute('aria-selected', 'false');
    node.setAttribute('aria-selected', 'true');
};
_TreeViewElement_handleNodeKeyboardEvent = function _TreeViewElement_handleNodeKeyboardEvent(event, node) {
    if (!node || this.getNodeType(node) !== 'leaf') {
        return;
    }
    switch (event.key) {
        case ' ':
        case 'Enter':
            if (this.getNodeDisabledValue(node)) {
                event.preventDefault();
                break;
            }
            if (this.nodeHasCheckBox(node)) {
                event.preventDefault();
                if (this.getNodeCheckedValue(node) === 'true') {
                    this.setNodeCheckedValue(node, 'false');
                }
                else {
                    this.setNodeCheckedValue(node, 'true');
                }
            }
            else if (node instanceof HTMLAnchorElement) {
                // simulate click on space
                node.click();
            }
            break;
    }
};
__decorate([
    target
], TreeViewElement.prototype, "formInputContainer", void 0);
__decorate([
    target
], TreeViewElement.prototype, "formInputPrototype", void 0);
TreeViewElement = __decorate([
    controller
], TreeViewElement);
export { TreeViewElement };
if (!window.customElements.get('tree-view')) {
    window.TreeViewElement = TreeViewElement;
    window.customElements.define('tree-view', TreeViewElement);
}
