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
var _ActionBarElement_instances, _ActionBarElement_focusZoneAbortController, _ActionBarElement_pendingUpdate, _ActionBarElement_performUpdate, _ActionBarElement_firstItem_get, _ActionBarElement_showItem, _ActionBarElement_hideItem, _ActionBarElement_menuItems_get;
import { controller, targets, target } from '@github/catalyst';
import { focusZone, FocusKeys } from '@primer/behaviors';
const instersectionObserver = new IntersectionObserver(entries => {
    for (const entry of entries) {
        const action = entry.target;
        if (entry.isIntersecting && action instanceof ActionBarElement) {
            action.update();
        }
    }
});
const resizeObserver = new ResizeObserver(entries => {
    for (const entry of entries) {
        const action = entry.target;
        if (action instanceof ActionBarElement) {
            action.update();
        }
    }
});
// These are definitely used, but eslint is dumb apparently
let ActionBarElement = class ActionBarElement extends HTMLElement {
    constructor() {
        super(...arguments);
        _ActionBarElement_instances.add(this);
        _ActionBarElement_focusZoneAbortController.set(this, null);
        _ActionBarElement_pendingUpdate.set(this, false);
    }
    connectedCallback() {
        resizeObserver.observe(this);
        instersectionObserver.observe(this);
        // This overflow visible is needed for browsers that don't support PopoverElement
        // to ensure the menu and tooltips are visible when the action bar is in a collapsed state
        // once popover is fully supported we can remove this.style.overflow = 'visible'
        this.style.overflow = 'visible';
        this.update();
    }
    disconnectedCallback() {
        resizeObserver.unobserve(this);
        instersectionObserver.unobserve(this);
    }
    menuItemClick(event) {
        const currentTarget = event.currentTarget;
        const id = currentTarget?.getAttribute('data-for');
        if (id) {
            document.getElementById(id)?.click();
        }
    }
    update() {
        if (__classPrivateFieldGet(this, _ActionBarElement_pendingUpdate, "f"))
            return;
        __classPrivateFieldSet(this, _ActionBarElement_pendingUpdate, true, "f");
        requestAnimationFrame(() => {
            __classPrivateFieldSet(this, _ActionBarElement_pendingUpdate, false, "f");
            __classPrivateFieldGet(this, _ActionBarElement_instances, "m", _ActionBarElement_performUpdate).call(this);
        });
    }
};
_ActionBarElement_focusZoneAbortController = new WeakMap();
_ActionBarElement_pendingUpdate = new WeakMap();
_ActionBarElement_instances = new WeakSet();
_ActionBarElement_performUpdate = function _ActionBarElement_performUpdate() {
    const firstItem = __classPrivateFieldGet(this, _ActionBarElement_instances, "a", _ActionBarElement_firstItem_get);
    if (!firstItem)
        return;
    const baseTop = firstItem.getBoundingClientRect().top;
    const cachedMenuItems = __classPrivateFieldGet(this, _ActionBarElement_instances, "a", _ActionBarElement_menuItems_get);
    // Snapshot geometry in one pass before mutating the DOM
    const snapshots = Array.from(this.items, el => ({
        top: el.getBoundingClientRect().top,
        isDivider: el.classList.contains('ActionBar-divider'),
    }));
    // Apply visibility changes after all reads are complete
    let prevWasDivider = false;
    for (let n = 0; n < snapshots.length; n++) {
        const snap = snapshots[n];
        if (snap.isDivider) {
            prevWasDivider = true;
            continue;
        }
        if (snap.top > baseTop) {
            __classPrivateFieldGet(this, _ActionBarElement_instances, "m", _ActionBarElement_hideItem).call(this, n, cachedMenuItems);
            if (this.moreMenu.hidden)
                this.moreMenu.hidden = false;
            if (prevWasDivider)
                __classPrivateFieldGet(this, _ActionBarElement_instances, "m", _ActionBarElement_hideItem).call(this, n - 1, cachedMenuItems);
        }
        else {
            __classPrivateFieldGet(this, _ActionBarElement_instances, "m", _ActionBarElement_showItem).call(this, n, cachedMenuItems);
            if (n === this.items.length - 1)
                this.moreMenu.hidden = true;
            if (prevWasDivider)
                __classPrivateFieldGet(this, _ActionBarElement_instances, "m", _ActionBarElement_showItem).call(this, n - 1, cachedMenuItems);
        }
        prevWasDivider = false;
    }
    if (__classPrivateFieldGet(this, _ActionBarElement_focusZoneAbortController, "f")) {
        __classPrivateFieldGet(this, _ActionBarElement_focusZoneAbortController, "f").abort();
    }
    __classPrivateFieldSet(this, _ActionBarElement_focusZoneAbortController, focusZone(this, {
        bindKeys: FocusKeys.ArrowHorizontal | FocusKeys.HomeAndEnd,
        focusOutBehavior: 'wrap',
        focusableElementFilter: element => {
            const idx = this.items.indexOf(element.parentElement);
            const elementIsVisibleItem = idx > -1 && this.items[idx].style.visibility === 'visible';
            const elementIsVisibleActionMenuInvoker = element === this.moreMenu.invokerElement && !this.moreMenu.hidden;
            return elementIsVisibleItem || elementIsVisibleActionMenuInvoker;
        },
    }), "f");
};
_ActionBarElement_firstItem_get = function _ActionBarElement_firstItem_get() {
    return this.items.find(el => !el.classList.contains('ActionBar-divider')) ?? null;
};
_ActionBarElement_showItem = function _ActionBarElement_showItem(index, menuItems) {
    const item = this.items[index];
    const menuItem = menuItems[index];
    if (!item || !menuItem)
        return;
    item.style.setProperty('visibility', 'visible');
    menuItem.hidden = true;
};
_ActionBarElement_hideItem = function _ActionBarElement_hideItem(index, menuItems) {
    const item = this.items[index];
    const menuItem = menuItems[index];
    if (!item || !menuItem)
        return;
    item.style.setProperty('visibility', 'hidden');
    menuItem.hidden = false;
};
_ActionBarElement_menuItems_get = function _ActionBarElement_menuItems_get() {
    return this.moreMenu.querySelectorAll('[role="menu"] > li');
};
__decorate([
    targets
], ActionBarElement.prototype, "items", void 0);
__decorate([
    target
], ActionBarElement.prototype, "itemContainer", void 0);
__decorate([
    target
], ActionBarElement.prototype, "moreMenu", void 0);
ActionBarElement = __decorate([
    controller('action-bar')
], ActionBarElement);
window.ActionBarElement = ActionBarElement;
