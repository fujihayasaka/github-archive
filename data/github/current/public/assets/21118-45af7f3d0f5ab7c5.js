performance.mark("js-parse-end:21118-45af7f3d0f5ab7c5.js");
"use strict";(globalThis.rspackChunk_github_ui_github_ui=globalThis.rspackChunk_github_ui_github_ui||[]).push([[21118],{294566(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-action-bar {
	white-space: nowrap;
	height: 100%;
}

.monaco-action-bar .actions-container {
	display: flex;
	margin: 0 auto;
	padding: 0;
	height: 100%;
	width: 100%;
	align-items: center;
}

.monaco-action-bar.vertical .actions-container {
	display: inline-block;
}

.monaco-action-bar .action-item {
	display: block;
	align-items: center;
	justify-content: center;
	cursor: pointer;
	position: relative;  /* DO NOT REMOVE - this is the key to preventing the ghosting icon bug in Chrome 42 */
}

.monaco-action-bar .action-item.disabled {
	cursor: default;
}

.monaco-action-bar .action-item .icon,
.monaco-action-bar .action-item .codicon {
	display: block;
}

.monaco-action-bar .action-item .codicon {
	display: flex;
	align-items: center;
	width: 16px;
	height: 16px;
}

.monaco-action-bar .action-label {
	display: flex;
	font-size: 11px;
	padding: 3px;
	border-radius: 5px;
}

.monaco-action-bar .action-item.disabled .action-label,
.monaco-action-bar .action-item.disabled .action-label::before,
.monaco-action-bar .action-item.disabled .action-label:hover {
	color: var(--vscode-disabledForeground);
}

/* Vertical actions */

.monaco-action-bar.vertical {
	text-align: left;
}

.monaco-action-bar.vertical .action-item {
	display: block;
}

.monaco-action-bar.vertical .action-label.separator {
	display: block;
	border-bottom: 1px solid #bbb;
	padding-top: 1px;
	margin-left: .8em;
	margin-right: .8em;
}

.monaco-action-bar .action-item .action-label.separator {
	width: 1px;
	height: 16px;
	margin: 5px 4px !important;
	cursor: default;
	min-width: 1px;
	padding: 0;
	background-color: #bbb;
}

.secondary-actions .monaco-action-bar .action-label {
	margin-left: 6px;
}

/* Action Items */
.monaco-action-bar .action-item.select-container {
	overflow: hidden; /* somehow the dropdown overflows its container, we prevent it here to not push */
	flex: 1;
	max-width: 170px;
	min-width: 60px;
	display: flex;
	align-items: center;
	justify-content: center;
	margin-right: 10px;
}

.monaco-action-bar .action-item.action-dropdown-item {
	display: flex;
}

.monaco-action-bar .action-item.action-dropdown-item > .action-dropdown-item-separator {
	display: flex;
	align-items: center;
	cursor: default;
}

.monaco-action-bar .action-item.action-dropdown-item > .action-dropdown-item-separator > div {
	width: 1px;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/actionbar/actionbar.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,mBAAmB;CACnB,YAAY;AACb;;AAEA;CACC,aAAa;CACb,cAAc;CACd,UAAU;CACV,YAAY;CACZ,WAAW;CACX,mBAAmB;AACpB;;AAEA;CACC,qBAAqB;AACtB;;AAEA;CACC,cAAc;CACd,mBAAmB;CACnB,uBAAuB;CACvB,eAAe;CACf,kBAAkB,GAAG,qFAAqF;AAC3G;;AAEA;CACC,eAAe;AAChB;;AAEA;;CAEC,cAAc;AACf;;AAEA;CACC,aAAa;CACb,mBAAmB;CACnB,WAAW;CACX,YAAY;AACb;;AAEA;CACC,aAAa;CACb,eAAe;CACf,YAAY;CACZ,kBAAkB;AACnB;;AAEA;;;CAGC,uCAAuC;AACxC;;AAEA,qBAAqB;;AAErB;CACC,gBAAgB;AACjB;;AAEA;CACC,cAAc;AACf;;AAEA;CACC,cAAc;CACd,6BAA6B;CAC7B,gBAAgB;CAChB,iBAAiB;CACjB,kBAAkB;AACnB;;AAEA;CACC,UAAU;CACV,YAAY;CACZ,0BAA0B;CAC1B,eAAe;CACf,cAAc;CACd,UAAU;CACV,sBAAsB;AACvB;;AAEA;CACC,gBAAgB;AACjB;;AAEA,iBAAiB;AACjB;CACC,gBAAgB,EAAE,iFAAiF;CACnG,OAAO;CACP,gBAAgB;CAChB,eAAe;CACf,aAAa;CACb,mBAAmB;CACnB,uBAAuB;CACvB,kBAAkB;AACnB;;AAEA;CACC,aAAa;AACd;;AAEA;CACC,aAAa;CACb,mBAAmB;CACnB,eAAe;AAChB;;AAEA;CACC,UAAU;AACX",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-action-bar {\n	white-space: nowrap;\n	height: 100%;\n}\n\n.monaco-action-bar .actions-container {\n	display: flex;\n	margin: 0 auto;\n	padding: 0;\n	height: 100%;\n	width: 100%;\n	align-items: center;\n}\n\n.monaco-action-bar.vertical .actions-container {\n	display: inline-block;\n}\n\n.monaco-action-bar .action-item {\n	display: block;\n	align-items: center;\n	justify-content: center;\n	cursor: pointer;\n	position: relative;  /* DO NOT REMOVE - this is the key to preventing the ghosting icon bug in Chrome 42 */\n}\n\n.monaco-action-bar .action-item.disabled {\n	cursor: default;\n}\n\n.monaco-action-bar .action-item .icon,\n.monaco-action-bar .action-item .codicon {\n	display: block;\n}\n\n.monaco-action-bar .action-item .codicon {\n	display: flex;\n	align-items: center;\n	width: 16px;\n	height: 16px;\n}\n\n.monaco-action-bar .action-label {\n	display: flex;\n	font-size: 11px;\n	padding: 3px;\n	border-radius: 5px;\n}\n\n.monaco-action-bar .action-item.disabled .action-label,\n.monaco-action-bar .action-item.disabled .action-label::before,\n.monaco-action-bar .action-item.disabled .action-label:hover {\n	color: var(--vscode-disabledForeground);\n}\n\n/* Vertical actions */\n\n.monaco-action-bar.vertical {\n	text-align: left;\n}\n\n.monaco-action-bar.vertical .action-item {\n	display: block;\n}\n\n.monaco-action-bar.vertical .action-label.separator {\n	display: block;\n	border-bottom: 1px solid #bbb;\n	padding-top: 1px;\n	margin-left: .8em;\n	margin-right: .8em;\n}\n\n.monaco-action-bar .action-item .action-label.separator {\n	width: 1px;\n	height: 16px;\n	margin: 5px 4px !important;\n	cursor: default;\n	min-width: 1px;\n	padding: 0;\n	background-color: #bbb;\n}\n\n.secondary-actions .monaco-action-bar .action-label {\n	margin-left: 6px;\n}\n\n/* Action Items */\n.monaco-action-bar .action-item.select-container {\n	overflow: hidden; /* somehow the dropdown overflows its container, we prevent it here to not push */\n	flex: 1;\n	max-width: 170px;\n	min-width: 60px;\n	display: flex;\n	align-items: center;\n	justify-content: center;\n	margin-right: 10px;\n}\n\n.monaco-action-bar .action-item.action-dropdown-item {\n	display: flex;\n}\n\n.monaco-action-bar .action-item.action-dropdown-item > .action-dropdown-item-separator {\n	display: flex;\n	align-items: center;\n	cursor: default;\n}\n\n.monaco-action-bar .action-item.action-dropdown-item > .action-dropdown-item-separator > div {\n	width: 1px;\n}\n"],sourceRoot:""}]),n.d(t,{},{A:a})},435038(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-aria-container {
	position: absolute; /* try to hide from window but not from screen readers */
	left:-999em;
}`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/aria/aria.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,kBAAkB,EAAE,wDAAwD;CAC5E,WAAW;AACZ",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-aria-container {\n	position: absolute; /* try to hide from window but not from screen readers */\n	left:-999em;\n}"],sourceRoot:""}]),n.d(t,{},{A:a})},18880(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-text-button {
	box-sizing: border-box;
	display: flex;
	width: 100%;
	padding: 4px;
	border-radius: 2px;
	text-align: center;
	cursor: pointer;
	justify-content: center;
	align-items: center;
	border: 1px solid var(--vscode-button-border, transparent);
	line-height: 18px;
}

.monaco-text-button:focus {
	outline-offset: 2px !important;
}

.monaco-text-button:hover {
	text-decoration: none !important;
}

.monaco-button.disabled:focus,
.monaco-button.disabled {
	opacity: 0.4 !important;
	cursor: default;
}

.monaco-text-button .codicon {
	margin: 0 0.2em;
	color: inherit !important;
}

.monaco-text-button.monaco-text-button-with-short-label {
	flex-direction: row;
	flex-wrap: wrap;
	padding: 0 4px;
	overflow: hidden;
	height: 28px;
}

.monaco-text-button.monaco-text-button-with-short-label > .monaco-button-label {
	flex-basis: 100%;
}

.monaco-text-button.monaco-text-button-with-short-label > .monaco-button-label-short {
	flex-grow: 1;
	width: 0;
	overflow: hidden;
}

.monaco-text-button.monaco-text-button-with-short-label > .monaco-button-label,
.monaco-text-button.monaco-text-button-with-short-label > .monaco-button-label-short {
	display: flex;
	justify-content: center;
	align-items: center;
	font-weight: normal;
	font-style: inherit;
	padding: 4px 0;
}

.monaco-button-dropdown {
	display: flex;
	cursor: pointer;
}

.monaco-button-dropdown.disabled {
	cursor: default;
}

.monaco-button-dropdown > .monaco-button:focus {
	outline-offset: -1px !important;
}

.monaco-button-dropdown.disabled > .monaco-button.disabled,
.monaco-button-dropdown.disabled > .monaco-button.disabled:focus,
.monaco-button-dropdown.disabled > .monaco-button-dropdown-separator {
	opacity: 0.4 !important;
}

.monaco-button-dropdown > .monaco-button.monaco-text-button {
	border-right-width: 0 !important;
}

.monaco-button-dropdown .monaco-button-dropdown-separator {
	padding: 4px 0;
	cursor: default;
}

.monaco-button-dropdown .monaco-button-dropdown-separator > div {
	height: 100%;
	width: 1px;
}

.monaco-button-dropdown > .monaco-button.monaco-dropdown-button {
	border: 1px solid var(--vscode-button-border, transparent);
	border-left-width: 0 !important;
	border-radius: 0 2px 2px 0;
	display: flex;
	align-items: center;
}

.monaco-button-dropdown > .monaco-button.monaco-text-button {
	border-radius: 2px 0 0 2px;
}

.monaco-description-button {
	display: flex;
	flex-direction: column;
	align-items: center;
	margin: 4px 5px; /* allows button focus outline to be visible */
}

.monaco-description-button .monaco-button-description {
	font-style: italic;
	font-size: 11px;
	padding: 4px 20px;
}

.monaco-description-button .monaco-button-label,
.monaco-description-button .monaco-button-description {
	display: flex;
	justify-content: center;
	align-items: center;
}

.monaco-description-button .monaco-button-label > .codicon,
.monaco-description-button .monaco-button-description > .codicon {
	margin: 0 0.2em;
	color: inherit !important;
}

/* default color styles - based on CSS variables */

.monaco-button.default-colors,
.monaco-button-dropdown.default-colors > .monaco-button{
	color: var(--vscode-button-foreground);
	background-color: var(--vscode-button-background);
}

.monaco-button.default-colors:hover,
.monaco-button-dropdown.default-colors > .monaco-button:hover {
	background-color: var(--vscode-button-hoverBackground);
}

.monaco-button.default-colors.secondary,
.monaco-button-dropdown.default-colors > .monaco-button.secondary {
	color: var(--vscode-button-secondaryForeground);
	background-color: var(--vscode-button-secondaryBackground);
}

.monaco-button.default-colors.secondary:hover,
.monaco-button-dropdown.default-colors > .monaco-button.secondary:hover {
	background-color: var(--vscode-button-secondaryHoverBackground);
}

.monaco-button-dropdown.default-colors .monaco-button-dropdown-separator {
	background-color: var(--vscode-button-background);
	border-top: 1px solid var(--vscode-button-border);
	border-bottom: 1px solid var(--vscode-button-border);
}

.monaco-button-dropdown.default-colors .monaco-button.secondary + .monaco-button-dropdown-separator {
	background-color: var(--vscode-button-secondaryBackground);
}

.monaco-button-dropdown.default-colors .monaco-button-dropdown-separator > div {
	background-color: var(--vscode-button-separator);
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/button/button.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,sBAAsB;CACtB,aAAa;CACb,WAAW;CACX,YAAY;CACZ,kBAAkB;CAClB,kBAAkB;CAClB,eAAe;CACf,uBAAuB;CACvB,mBAAmB;CACnB,0DAA0D;CAC1D,iBAAiB;AAClB;;AAEA;CACC,8BAA8B;AAC/B;;AAEA;CACC,gCAAgC;AACjC;;AAEA;;CAEC,uBAAuB;CACvB,eAAe;AAChB;;AAEA;CACC,eAAe;CACf,yBAAyB;AAC1B;;AAEA;CACC,mBAAmB;CACnB,eAAe;CACf,cAAc;CACd,gBAAgB;CAChB,YAAY;AACb;;AAEA;CACC,gBAAgB;AACjB;;AAEA;CACC,YAAY;CACZ,QAAQ;CACR,gBAAgB;AACjB;;AAEA;;CAEC,aAAa;CACb,uBAAuB;CACvB,mBAAmB;CACnB,mBAAmB;CACnB,mBAAmB;CACnB,cAAc;AACf;;AAEA;CACC,aAAa;CACb,eAAe;AAChB;;AAEA;CACC,eAAe;AAChB;;AAEA;CACC,+BAA+B;AAChC;;AAEA;;;CAGC,uBAAuB;AACxB;;AAEA;CACC,gCAAgC;AACjC;;AAEA;CACC,cAAc;CACd,eAAe;AAChB;;AAEA;CACC,YAAY;CACZ,UAAU;AACX;;AAEA;CACC,0DAA0D;CAC1D,+BAA+B;CAC/B,0BAA0B;CAC1B,aAAa;CACb,mBAAmB;AACpB;;AAEA;CACC,0BAA0B;AAC3B;;AAEA;CACC,aAAa;CACb,sBAAsB;CACtB,mBAAmB;CACnB,eAAe,EAAE,8CAA8C;AAChE;;AAEA;CACC,kBAAkB;CAClB,eAAe;CACf,iBAAiB;AAClB;;AAEA;;CAEC,aAAa;CACb,uBAAuB;CACvB,mBAAmB;AACpB;;AAEA;;CAEC,eAAe;CACf,yBAAyB;AAC1B;;AAEA,kDAAkD;;AAElD;;CAEC,sCAAsC;CACtC,iDAAiD;AAClD;;AAEA;;CAEC,sDAAsD;AACvD;;AAEA;;CAEC,+CAA+C;CAC/C,0DAA0D;AAC3D;;AAEA;;CAEC,+DAA+D;AAChE;;AAEA;CACC,iDAAiD;CACjD,iDAAiD;CACjD,oDAAoD;AACrD;;AAEA;CACC,0DAA0D;AAC3D;;AAEA;CACC,gDAAgD;AACjD",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-text-button {\n	box-sizing: border-box;\n	display: flex;\n	width: 100%;\n	padding: 4px;\n	border-radius: 2px;\n	text-align: center;\n	cursor: pointer;\n	justify-content: center;\n	align-items: center;\n	border: 1px solid var(--vscode-button-border, transparent);\n	line-height: 18px;\n}\n\n.monaco-text-button:focus {\n	outline-offset: 2px !important;\n}\n\n.monaco-text-button:hover {\n	text-decoration: none !important;\n}\n\n.monaco-button.disabled:focus,\n.monaco-button.disabled {\n	opacity: 0.4 !important;\n	cursor: default;\n}\n\n.monaco-text-button .codicon {\n	margin: 0 0.2em;\n	color: inherit !important;\n}\n\n.monaco-text-button.monaco-text-button-with-short-label {\n	flex-direction: row;\n	flex-wrap: wrap;\n	padding: 0 4px;\n	overflow: hidden;\n	height: 28px;\n}\n\n.monaco-text-button.monaco-text-button-with-short-label > .monaco-button-label {\n	flex-basis: 100%;\n}\n\n.monaco-text-button.monaco-text-button-with-short-label > .monaco-button-label-short {\n	flex-grow: 1;\n	width: 0;\n	overflow: hidden;\n}\n\n.monaco-text-button.monaco-text-button-with-short-label > .monaco-button-label,\n.monaco-text-button.monaco-text-button-with-short-label > .monaco-button-label-short {\n	display: flex;\n	justify-content: center;\n	align-items: center;\n	font-weight: normal;\n	font-style: inherit;\n	padding: 4px 0;\n}\n\n.monaco-button-dropdown {\n	display: flex;\n	cursor: pointer;\n}\n\n.monaco-button-dropdown.disabled {\n	cursor: default;\n}\n\n.monaco-button-dropdown > .monaco-button:focus {\n	outline-offset: -1px !important;\n}\n\n.monaco-button-dropdown.disabled > .monaco-button.disabled,\n.monaco-button-dropdown.disabled > .monaco-button.disabled:focus,\n.monaco-button-dropdown.disabled > .monaco-button-dropdown-separator {\n	opacity: 0.4 !important;\n}\n\n.monaco-button-dropdown > .monaco-button.monaco-text-button {\n	border-right-width: 0 !important;\n}\n\n.monaco-button-dropdown .monaco-button-dropdown-separator {\n	padding: 4px 0;\n	cursor: default;\n}\n\n.monaco-button-dropdown .monaco-button-dropdown-separator > div {\n	height: 100%;\n	width: 1px;\n}\n\n.monaco-button-dropdown > .monaco-button.monaco-dropdown-button {\n	border: 1px solid var(--vscode-button-border, transparent);\n	border-left-width: 0 !important;\n	border-radius: 0 2px 2px 0;\n	display: flex;\n	align-items: center;\n}\n\n.monaco-button-dropdown > .monaco-button.monaco-text-button {\n	border-radius: 2px 0 0 2px;\n}\n\n.monaco-description-button {\n	display: flex;\n	flex-direction: column;\n	align-items: center;\n	margin: 4px 5px; /* allows button focus outline to be visible */\n}\n\n.monaco-description-button .monaco-button-description {\n	font-style: italic;\n	font-size: 11px;\n	padding: 4px 20px;\n}\n\n.monaco-description-button .monaco-button-label,\n.monaco-description-button .monaco-button-description {\n	display: flex;\n	justify-content: center;\n	align-items: center;\n}\n\n.monaco-description-button .monaco-button-label > .codicon,\n.monaco-description-button .monaco-button-description > .codicon {\n	margin: 0 0.2em;\n	color: inherit !important;\n}\n\n/* default color styles - based on CSS variables */\n\n.monaco-button.default-colors,\n.monaco-button-dropdown.default-colors > .monaco-button{\n	color: var(--vscode-button-foreground);\n	background-color: var(--vscode-button-background);\n}\n\n.monaco-button.default-colors:hover,\n.monaco-button-dropdown.default-colors > .monaco-button:hover {\n	background-color: var(--vscode-button-hoverBackground);\n}\n\n.monaco-button.default-colors.secondary,\n.monaco-button-dropdown.default-colors > .monaco-button.secondary {\n	color: var(--vscode-button-secondaryForeground);\n	background-color: var(--vscode-button-secondaryBackground);\n}\n\n.monaco-button.default-colors.secondary:hover,\n.monaco-button-dropdown.default-colors > .monaco-button.secondary:hover {\n	background-color: var(--vscode-button-secondaryHoverBackground);\n}\n\n.monaco-button-dropdown.default-colors .monaco-button-dropdown-separator {\n	background-color: var(--vscode-button-background);\n	border-top: 1px solid var(--vscode-button-border);\n	border-bottom: 1px solid var(--vscode-button-border);\n}\n\n.monaco-button-dropdown.default-colors .monaco-button.secondary + .monaco-button-dropdown-separator {\n	background-color: var(--vscode-button-secondaryBackground);\n}\n\n.monaco-button-dropdown.default-colors .monaco-button-dropdown-separator > div {\n	background-color: var(--vscode-button-separator);\n}\n"],sourceRoot:""}]),n.d(t,{},{A:a})},300714(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.codicon-wrench-subaction {
	opacity: 0.5;
}

@keyframes codicon-spin {
	100% {
		transform:rotate(360deg);
	}
}

.codicon-sync.codicon-modifier-spin,
.codicon-loading.codicon-modifier-spin,
.codicon-gear.codicon-modifier-spin,
.codicon-notebook-state-executing.codicon-modifier-spin {
	/* Use steps to throttle FPS to reduce CPU usage */
	animation: codicon-spin 1.5s steps(30) infinite;
}

.codicon-modifier-disabled {
	opacity: 0.4;
}

/* custom speed & easing for loading icon */
.codicon-loading,
.codicon-tree-item-loading::before {
	animation-duration: 1s !important;
	animation-timing-function: cubic-bezier(0.53, 0.21, 0.29, 0.67) !important;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/codicons/codicon/codicon-modifiers.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,YAAY;AACb;;AAEA;CACC;EACC,wBAAwB;CACzB;AACD;;AAEA;;;;CAIC,kDAAkD;CAClD,+CAA+C;AAChD;;AAEA;CACC,YAAY;AACb;;AAEA,2CAA2C;AAC3C;;CAEC,iCAAiC;CACjC,0EAA0E;AAC3E",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.codicon-wrench-subaction {\n	opacity: 0.5;\n}\n\n@keyframes codicon-spin {\n	100% {\n		transform:rotate(360deg);\n	}\n}\n\n.codicon-sync.codicon-modifier-spin,\n.codicon-loading.codicon-modifier-spin,\n.codicon-gear.codicon-modifier-spin,\n.codicon-notebook-state-executing.codicon-modifier-spin {\n	/* Use steps to throttle FPS to reduce CPU usage */\n	animation: codicon-spin 1.5s steps(30) infinite;\n}\n\n.codicon-modifier-disabled {\n	opacity: 0.4;\n}\n\n/* custom speed & easing for loading icon */\n.codicon-loading,\n.codicon-tree-item-loading::before {\n	animation-duration: 1s !important;\n	animation-timing-function: cubic-bezier(0.53, 0.21, 0.29, 0.67) !important;\n}\n"],sourceRoot:""}]),n.d(t,{},{A:a})},612171(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s),r=n(504417),l=n.n(r),c=new URL(n(818880),n.b),h=a()(i()),d=l()(c);h.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

@font-face {
	font-family: "codicon";
	font-display: block;
	src: url(${d}) format("truetype");
}

.codicon[class*='codicon-'] {
	font: normal normal normal 16px/1 codicon;
	display: inline-block;
	text-decoration: none;
	text-rendering: auto;
	text-align: center;
	text-transform: none;
	-webkit-font-smoothing: antialiased;
	-moz-osx-font-smoothing: grayscale;
	user-select: none;
	-webkit-user-select: none;
}

/* icon rules are dynamically created by the platform theme service (see iconsStyleSheet.ts) */
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/codicons/codicon/codicon.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,sBAAsB;CACtB,mBAAmB;CACnB,+DAA0C;AAC3C;;AAEA;CACC,yCAAyC;CACzC,qBAAqB;CACrB,qBAAqB;CACrB,oBAAoB;CACpB,kBAAkB;CAClB,oBAAoB;CACpB,mCAAmC;CACnC,kCAAkC;CAClC,iBAAiB;CACjB,yBAAyB;AAC1B;;AAEA,8FAA8F",sourcesContent:['/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n@font-face {\n	font-family: "codicon";\n	font-display: block;\n	src: url(./codicon.ttf) format("truetype");\n}\n\n.codicon[class*=\'codicon-\'] {\n	font: normal normal normal 16px/1 codicon;\n	display: inline-block;\n	text-decoration: none;\n	text-rendering: auto;\n	text-align: center;\n	text-transform: none;\n	-webkit-font-smoothing: antialiased;\n	-moz-osx-font-smoothing: grayscale;\n	user-select: none;\n	-webkit-user-select: none;\n}\n\n/* icon rules are dynamically created by the platform theme service (see iconsStyleSheet.ts) */\n'],sourceRoot:""}]),n.d(t,{},{A:h})},908970(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.context-view {
	position: absolute;
}

.context-view.fixed {
	all: initial;
	font-family: inherit;
	font-size: 13px;
	position: fixed;
	color: inherit;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/contextview/contextview.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,kBAAkB;AACnB;;AAEA;CACC,YAAY;CACZ,oBAAoB;CACpB,eAAe;CACf,eAAe;CACf,cAAc;AACf",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.context-view {\n	position: absolute;\n}\n\n.context-view.fixed {\n	all: initial;\n	font-family: inherit;\n	font-size: 13px;\n	position: fixed;\n	color: inherit;\n}\n"],sourceRoot:""}]),n.d(t,{},{A:a})},81684(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-count-badge {
	padding: 3px 6px;
	border-radius: 11px;
	font-size: 11px;
	min-width: 18px;
	min-height: 18px;
	line-height: 11px;
	font-weight: normal;
	text-align: center;
	display: inline-block;
	box-sizing: border-box;
}

.monaco-count-badge.long {
	padding: 2px 3px;
	border-radius: 2px;
	min-height: auto;
	line-height: normal;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/countBadge/countBadge.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,gBAAgB;CAChB,mBAAmB;CACnB,eAAe;CACf,eAAe;CACf,gBAAgB;CAChB,iBAAiB;CACjB,mBAAmB;CACnB,kBAAkB;CAClB,qBAAqB;CACrB,sBAAsB;AACvB;;AAEA;CACC,gBAAgB;CAChB,kBAAkB;CAClB,gBAAgB;CAChB,mBAAmB;AACpB",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-count-badge {\n	padding: 3px 6px;\n	border-radius: 11px;\n	font-size: 11px;\n	min-width: 18px;\n	min-height: 18px;\n	line-height: 11px;\n	font-weight: normal;\n	text-align: center;\n	display: inline-block;\n	box-sizing: border-box;\n}\n\n.monaco-count-badge.long {\n	padding: 2px 3px;\n	border-radius: 2px;\n	min-height: auto;\n	line-height: normal;\n}\n"],sourceRoot:""}]),n.d(t,{},{A:a})},979862(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-dropdown {
	height: 100%;
	padding: 0;
}

.monaco-dropdown > .dropdown-label {
	cursor: pointer;
	height: 100%;
	display: flex;
	align-items: center;
	justify-content: center;
}

.monaco-dropdown > .dropdown-label > .action-label.disabled {
	cursor: default;
}

.monaco-dropdown-with-primary {
	display: flex !important;
	flex-direction: row;
	border-radius: 5px;
}

.monaco-dropdown-with-primary > .action-container > .action-label {
	margin-right: 0;
}

.monaco-dropdown-with-primary > .dropdown-action-container > .monaco-dropdown > .dropdown-label .codicon[class*='codicon-'] {
	font-size: 12px;
	padding-left: 0px;
	padding-right: 0px;
	line-height: 16px;
	margin-left: -3px;
}

.monaco-dropdown-with-primary > .dropdown-action-container > .monaco-dropdown > .dropdown-label > .action-label {
	display: block;
	background-size: 16px;
	background-position: center center;
	background-repeat: no-repeat;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/dropdown/dropdown.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,YAAY;CACZ,UAAU;AACX;;AAEA;CACC,eAAe;CACf,YAAY;CACZ,aAAa;CACb,mBAAmB;CACnB,uBAAuB;AACxB;;AAEA;CACC,eAAe;AAChB;;AAEA;CACC,wBAAwB;CACxB,mBAAmB;CACnB,kBAAkB;AACnB;;AAEA;CACC,eAAe;AAChB;;AAEA;CACC,eAAe;CACf,iBAAiB;CACjB,kBAAkB;CAClB,iBAAiB;CACjB,iBAAiB;AAClB;;AAEA;CACC,cAAc;CACd,qBAAqB;CACrB,kCAAkC;CAClC,4BAA4B;AAC7B",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-dropdown {\n	height: 100%;\n	padding: 0;\n}\n\n.monaco-dropdown > .dropdown-label {\n	cursor: pointer;\n	height: 100%;\n	display: flex;\n	align-items: center;\n	justify-content: center;\n}\n\n.monaco-dropdown > .dropdown-label > .action-label.disabled {\n	cursor: default;\n}\n\n.monaco-dropdown-with-primary {\n	display: flex !important;\n	flex-direction: row;\n	border-radius: 5px;\n}\n\n.monaco-dropdown-with-primary > .action-container > .action-label {\n	margin-right: 0;\n}\n\n.monaco-dropdown-with-primary > .dropdown-action-container > .monaco-dropdown > .dropdown-label .codicon[class*='codicon-'] {\n	font-size: 12px;\n	padding-left: 0px;\n	padding-right: 0px;\n	line-height: 16px;\n	margin-left: -3px;\n}\n\n.monaco-dropdown-with-primary > .dropdown-action-container > .monaco-dropdown > .dropdown-label > .action-label {\n	display: block;\n	background-size: 16px;\n	background-position: center center;\n	background-repeat: no-repeat;\n}\n"],sourceRoot:""}]),n.d(t,{},{A:a})},408474(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
/* ---------- Find input ---------- */

.monaco-findInput {
	position: relative;
}

.monaco-findInput .monaco-inputbox {
	font-size: 13px;
	width: 100%;
}

.monaco-findInput > .controls {
	position: absolute;
	top: 3px;
	right: 2px;
}

.vs .monaco-findInput.disabled {
	background-color: #E1E1E1;
}

/* Theming */
.vs-dark .monaco-findInput.disabled {
	background-color: #333;
}

/* Highlighting */
.monaco-findInput.highlight-0 .controls,
.hc-light .monaco-findInput.highlight-0 .controls {
	animation: monaco-findInput-highlight-0 100ms linear 0s;
}

.monaco-findInput.highlight-1 .controls,
.hc-light .monaco-findInput.highlight-1 .controls {
	animation: monaco-findInput-highlight-1 100ms linear 0s;
}

.hc-black .monaco-findInput.highlight-0 .controls,
.vs-dark  .monaco-findInput.highlight-0 .controls {
	animation: monaco-findInput-highlight-dark-0 100ms linear 0s;
}

.hc-black .monaco-findInput.highlight-1 .controls,
.vs-dark  .monaco-findInput.highlight-1 .controls {
	animation: monaco-findInput-highlight-dark-1 100ms linear 0s;
}

@keyframes monaco-findInput-highlight-0 {
	0% { background: rgba(253, 255, 0, 0.8); }
	100% { background: transparent; }
}
@keyframes monaco-findInput-highlight-1 {
	0% { background: rgba(253, 255, 0, 0.8); }
	/* Made intentionally different such that the CSS minifier does not collapse the two animations into a single one*/
	99% { background: transparent; }
}

@keyframes monaco-findInput-highlight-dark-0 {
	0% { background: rgba(255, 255, 255, 0.44); }
	100% { background: transparent; }
}
@keyframes monaco-findInput-highlight-dark-1 {
	0% { background: rgba(255, 255, 255, 0.44); }
	/* Made intentionally different such that the CSS minifier does not collapse the two animations into a single one*/
	99% { background: transparent; }
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/findinput/findInput.css"],names:[],mappings:"AAAA;;;+FAG+F;AAC/F,qCAAqC;;AAErC;CACC,kBAAkB;AACnB;;AAEA;CACC,eAAe;CACf,WAAW;AACZ;;AAEA;CACC,kBAAkB;CAClB,QAAQ;CACR,UAAU;AACX;;AAEA;CACC,yBAAyB;AAC1B;;AAEA,YAAY;AACZ;CACC,sBAAsB;AACvB;;AAEA,iBAAiB;AACjB;;CAEC,uDAAuD;AACxD;;AAEA;;CAEC,uDAAuD;AACxD;;AAEA;;CAEC,4DAA4D;AAC7D;;AAEA;;CAEC,4DAA4D;AAC7D;;AAEA;CACC,KAAK,kCAAkC,EAAE;CACzC,OAAO,uBAAuB,EAAE;AACjC;AACA;CACC,KAAK,kCAAkC,EAAE;CACzC,kHAAkH;CAClH,MAAM,uBAAuB,EAAE;AAChC;;AAEA;CACC,KAAK,qCAAqC,EAAE;CAC5C,OAAO,uBAAuB,EAAE;AACjC;AACA;CACC,KAAK,qCAAqC,EAAE;CAC5C,kHAAkH;CAClH,MAAM,uBAAuB,EAAE;AAChC",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n/* ---------- Find input ---------- */\n\n.monaco-findInput {\n	position: relative;\n}\n\n.monaco-findInput .monaco-inputbox {\n	font-size: 13px;\n	width: 100%;\n}\n\n.monaco-findInput > .controls {\n	position: absolute;\n	top: 3px;\n	right: 2px;\n}\n\n.vs .monaco-findInput.disabled {\n	background-color: #E1E1E1;\n}\n\n/* Theming */\n.vs-dark .monaco-findInput.disabled {\n	background-color: #333;\n}\n\n/* Highlighting */\n.monaco-findInput.highlight-0 .controls,\n.hc-light .monaco-findInput.highlight-0 .controls {\n	animation: monaco-findInput-highlight-0 100ms linear 0s;\n}\n\n.monaco-findInput.highlight-1 .controls,\n.hc-light .monaco-findInput.highlight-1 .controls {\n	animation: monaco-findInput-highlight-1 100ms linear 0s;\n}\n\n.hc-black .monaco-findInput.highlight-0 .controls,\n.vs-dark  .monaco-findInput.highlight-0 .controls {\n	animation: monaco-findInput-highlight-dark-0 100ms linear 0s;\n}\n\n.hc-black .monaco-findInput.highlight-1 .controls,\n.vs-dark  .monaco-findInput.highlight-1 .controls {\n	animation: monaco-findInput-highlight-dark-1 100ms linear 0s;\n}\n\n@keyframes monaco-findInput-highlight-0 {\n	0% { background: rgba(253, 255, 0, 0.8); }\n	100% { background: transparent; }\n}\n@keyframes monaco-findInput-highlight-1 {\n	0% { background: rgba(253, 255, 0, 0.8); }\n	/* Made intentionally different such that the CSS minifier does not collapse the two animations into a single one*/\n	99% { background: transparent; }\n}\n\n@keyframes monaco-findInput-highlight-dark-0 {\n	0% { background: rgba(255, 255, 255, 0.44); }\n	100% { background: transparent; }\n}\n@keyframes monaco-findInput-highlight-dark-1 {\n	0% { background: rgba(255, 255, 255, 0.44); }\n	/* Made intentionally different such that the CSS minifier does not collapse the two animations into a single one*/\n	99% { background: transparent; }\n}\n"],sourceRoot:""}]),n.d(t,{},{A:a})},858694(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-hover {
	cursor: default;
	position: absolute;
	overflow: hidden;
	user-select: text;
	-webkit-user-select: text;
	box-sizing: border-box;
	animation: fadein 100ms linear;
	line-height: 1.5em;
	white-space: var(--vscode-hover-whiteSpace, normal);
}

.monaco-hover.hidden {
	display: none;
}

.monaco-hover a:hover:not(.disabled) {
	cursor: pointer;
}

.monaco-hover .hover-contents:not(.html-hover-contents) {
	padding: 4px 8px;
}

.monaco-hover .markdown-hover > .hover-contents:not(.code-hover-contents) {
	max-width: var(--vscode-hover-maxWidth, 500px);
	word-wrap: break-word;
}

.monaco-hover .markdown-hover > .hover-contents:not(.code-hover-contents) hr {
	min-width: 100%;
}

.monaco-hover p,
.monaco-hover .code,
.monaco-hover ul,
.monaco-hover h1,
.monaco-hover h2,
.monaco-hover h3,
.monaco-hover h4,
.monaco-hover h5,
.monaco-hover h6 {
	margin: 8px 0;
}

.monaco-hover h1,
.monaco-hover h2,
.monaco-hover h3,
.monaco-hover h4,
.monaco-hover h5,
.monaco-hover h6 {
	line-height: 1.1;
}

.monaco-hover code {
	font-family: var(--monaco-monospace-font);
}

.monaco-hover hr {
	box-sizing: border-box;
	border-left: 0px;
	border-right: 0px;
	margin-top: 4px;
	margin-bottom: -4px;
	margin-left: -8px;
	margin-right: -8px;
	height: 1px;
}

.monaco-hover p:first-child,
.monaco-hover .code:first-child,
.monaco-hover ul:first-child {
	margin-top: 0;
}

.monaco-hover p:last-child,
.monaco-hover .code:last-child,
.monaco-hover ul:last-child {
	margin-bottom: 0;
}

/* MarkupContent Layout */
.monaco-hover ul {
	padding-left: 20px;
}
.monaco-hover ol {
	padding-left: 20px;
}

.monaco-hover li > p {
	margin-bottom: 0;
}

.monaco-hover li > ul {
	margin-top: 0;
}

.monaco-hover code {
	border-radius: 3px;
	padding: 0 0.4em;
}

.monaco-hover .monaco-tokenized-source {
	white-space: var(--vscode-hover-sourceWhiteSpace, pre-wrap);
}

.monaco-hover .hover-row.status-bar {
	font-size: 12px;
	line-height: 22px;
}

.monaco-hover .hover-row.status-bar .info {
	font-style: italic;
	padding: 0px 8px;
}

.monaco-hover .hover-row.status-bar .actions {
	display: flex;
	padding: 0px 8px;
	width: 100%;
}

.monaco-hover .hover-row.status-bar .actions .action-container {
	margin-right: 16px;
	cursor: pointer;
}

.monaco-hover .hover-row.status-bar .actions .action-container .action .icon {
	padding-right: 4px;
}

.monaco-hover .markdown-hover .hover-contents .codicon {
	color: inherit;
	font-size: inherit;
	vertical-align: middle;
}

.monaco-hover .hover-contents a.code-link:hover,
.monaco-hover .hover-contents a.code-link {
	color: inherit;
}

.monaco-hover .hover-contents a.code-link:before {
	content: '(';
}

.monaco-hover .hover-contents a.code-link:after {
	content: ')';
}

.monaco-hover .hover-contents a.code-link > span {
	text-decoration: underline;
	/** Hack to force underline to show **/
	border-bottom: 1px solid transparent;
	text-underline-position: under;
	color: var(--vscode-textLink-foreground);
}

.monaco-hover .hover-contents a.code-link > span:hover {
	color: var(--vscode-textLink-activeForeground);
}

/** Spans in markdown hovers need a margin-bottom to avoid looking cramped: https://github.com/microsoft/vscode/issues/101496 **/
.monaco-hover .markdown-hover .hover-contents:not(.code-hover-contents):not(.html-hover-contents) span {
	margin-bottom: 4px;
	display: inline-block;
}

.monaco-hover-content {
	padding-right: 2px;
	padding-bottom: 2px;
	box-sizing: border-box;
}

.monaco-hover-content .action-container a {
	-webkit-user-select: none;
	user-select: none;
}

.monaco-hover-content .action-container.disabled {
	pointer-events: none;
	opacity: 0.4;
	cursor: default;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/hover/hoverWidget.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,eAAe;CACf,kBAAkB;CAClB,gBAAgB;CAChB,iBAAiB;CACjB,yBAAyB;CACzB,sBAAsB;CACtB,8BAA8B;CAC9B,kBAAkB;CAClB,mDAAmD;AACpD;;AAEA;CACC,aAAa;AACd;;AAEA;CACC,eAAe;AAChB;;AAEA;CACC,gBAAgB;AACjB;;AAEA;CACC,8CAA8C;CAC9C,qBAAqB;AACtB;;AAEA;CACC,eAAe;AAChB;;AAEA;;;;;;;;;CASC,aAAa;AACd;;AAEA;;;;;;CAMC,gBAAgB;AACjB;;AAEA;CACC,yCAAyC;AAC1C;;AAEA;CACC,sBAAsB;CACtB,gBAAgB;CAChB,iBAAiB;CACjB,eAAe;CACf,mBAAmB;CACnB,iBAAiB;CACjB,kBAAkB;CAClB,WAAW;AACZ;;AAEA;;;CAGC,aAAa;AACd;;AAEA;;;CAGC,gBAAgB;AACjB;;AAEA,yBAAyB;AACzB;CACC,kBAAkB;AACnB;AACA;CACC,kBAAkB;AACnB;;AAEA;CACC,gBAAgB;AACjB;;AAEA;CACC,aAAa;AACd;;AAEA;CACC,kBAAkB;CAClB,gBAAgB;AACjB;;AAEA;CACC,2DAA2D;AAC5D;;AAEA;CACC,eAAe;CACf,iBAAiB;AAClB;;AAEA;CACC,kBAAkB;CAClB,gBAAgB;AACjB;;AAEA;CACC,aAAa;CACb,gBAAgB;CAChB,WAAW;AACZ;;AAEA;CACC,kBAAkB;CAClB,eAAe;AAChB;;AAEA;CACC,kBAAkB;AACnB;;AAEA;CACC,cAAc;CACd,kBAAkB;CAClB,sBAAsB;AACvB;;AAEA;;CAEC,cAAc;AACf;;AAEA;CACC,YAAY;AACb;;AAEA;CACC,YAAY;AACb;;AAEA;CACC,0BAA0B;CAC1B,sCAAsC;CACtC,oCAAoC;CACpC,8BAA8B;CAC9B,wCAAwC;AACzC;;AAEA;CACC,8CAA8C;AAC/C;;AAEA,gIAAgI;AAChI;CACC,kBAAkB;CAClB,qBAAqB;AACtB;;AAEA;CACC,kBAAkB;CAClB,mBAAmB;CACnB,sBAAsB;AACvB;;AAEA;CACC,yBAAyB;CACzB,iBAAiB;AAClB;;AAEA;CACC,oBAAoB;CACpB,YAAY;CACZ,eAAe;AAChB",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-hover {\n	cursor: default;\n	position: absolute;\n	overflow: hidden;\n	user-select: text;\n	-webkit-user-select: text;\n	box-sizing: border-box;\n	animation: fadein 100ms linear;\n	line-height: 1.5em;\n	white-space: var(--vscode-hover-whiteSpace, normal);\n}\n\n.monaco-hover.hidden {\n	display: none;\n}\n\n.monaco-hover a:hover:not(.disabled) {\n	cursor: pointer;\n}\n\n.monaco-hover .hover-contents:not(.html-hover-contents) {\n	padding: 4px 8px;\n}\n\n.monaco-hover .markdown-hover > .hover-contents:not(.code-hover-contents) {\n	max-width: var(--vscode-hover-maxWidth, 500px);\n	word-wrap: break-word;\n}\n\n.monaco-hover .markdown-hover > .hover-contents:not(.code-hover-contents) hr {\n	min-width: 100%;\n}\n\n.monaco-hover p,\n.monaco-hover .code,\n.monaco-hover ul,\n.monaco-hover h1,\n.monaco-hover h2,\n.monaco-hover h3,\n.monaco-hover h4,\n.monaco-hover h5,\n.monaco-hover h6 {\n	margin: 8px 0;\n}\n\n.monaco-hover h1,\n.monaco-hover h2,\n.monaco-hover h3,\n.monaco-hover h4,\n.monaco-hover h5,\n.monaco-hover h6 {\n	line-height: 1.1;\n}\n\n.monaco-hover code {\n	font-family: var(--monaco-monospace-font);\n}\n\n.monaco-hover hr {\n	box-sizing: border-box;\n	border-left: 0px;\n	border-right: 0px;\n	margin-top: 4px;\n	margin-bottom: -4px;\n	margin-left: -8px;\n	margin-right: -8px;\n	height: 1px;\n}\n\n.monaco-hover p:first-child,\n.monaco-hover .code:first-child,\n.monaco-hover ul:first-child {\n	margin-top: 0;\n}\n\n.monaco-hover p:last-child,\n.monaco-hover .code:last-child,\n.monaco-hover ul:last-child {\n	margin-bottom: 0;\n}\n\n/* MarkupContent Layout */\n.monaco-hover ul {\n	padding-left: 20px;\n}\n.monaco-hover ol {\n	padding-left: 20px;\n}\n\n.monaco-hover li > p {\n	margin-bottom: 0;\n}\n\n.monaco-hover li > ul {\n	margin-top: 0;\n}\n\n.monaco-hover code {\n	border-radius: 3px;\n	padding: 0 0.4em;\n}\n\n.monaco-hover .monaco-tokenized-source {\n	white-space: var(--vscode-hover-sourceWhiteSpace, pre-wrap);\n}\n\n.monaco-hover .hover-row.status-bar {\n	font-size: 12px;\n	line-height: 22px;\n}\n\n.monaco-hover .hover-row.status-bar .info {\n	font-style: italic;\n	padding: 0px 8px;\n}\n\n.monaco-hover .hover-row.status-bar .actions {\n	display: flex;\n	padding: 0px 8px;\n	width: 100%;\n}\n\n.monaco-hover .hover-row.status-bar .actions .action-container {\n	margin-right: 16px;\n	cursor: pointer;\n}\n\n.monaco-hover .hover-row.status-bar .actions .action-container .action .icon {\n	padding-right: 4px;\n}\n\n.monaco-hover .markdown-hover .hover-contents .codicon {\n	color: inherit;\n	font-size: inherit;\n	vertical-align: middle;\n}\n\n.monaco-hover .hover-contents a.code-link:hover,\n.monaco-hover .hover-contents a.code-link {\n	color: inherit;\n}\n\n.monaco-hover .hover-contents a.code-link:before {\n	content: '(';\n}\n\n.monaco-hover .hover-contents a.code-link:after {\n	content: ')';\n}\n\n.monaco-hover .hover-contents a.code-link > span {\n	text-decoration: underline;\n	/** Hack to force underline to show **/\n	border-bottom: 1px solid transparent;\n	text-underline-position: under;\n	color: var(--vscode-textLink-foreground);\n}\n\n.monaco-hover .hover-contents a.code-link > span:hover {\n	color: var(--vscode-textLink-activeForeground);\n}\n\n/** Spans in markdown hovers need a margin-bottom to avoid looking cramped: https://github.com/microsoft/vscode/issues/101496 **/\n.monaco-hover .markdown-hover .hover-contents:not(.code-hover-contents):not(.html-hover-contents) span {\n	margin-bottom: 4px;\n	display: inline-block;\n}\n\n.monaco-hover-content {\n	padding-right: 2px;\n	padding-bottom: 2px;\n	box-sizing: border-box;\n}\n\n.monaco-hover-content .action-container a {\n	-webkit-user-select: none;\n	user-select: none;\n}\n\n.monaco-hover-content .action-container.disabled {\n	pointer-events: none;\n	opacity: 0.4;\n	cursor: default;\n}\n"],sourceRoot:""}]),n.d(t,{},{A:a})},348134(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

/* ---------- Icon label ---------- */

.monaco-icon-label {
	display: flex; /* required for icons support :before rule */
	overflow: hidden;
	text-overflow: ellipsis;
}

.monaco-icon-label::before {

	/* svg icons rendered as background image */
	background-size: 16px;
	background-position: left center;
	background-repeat: no-repeat;
	padding-right: 6px;
	width: 16px;
	height: 22px;
	line-height: inherit !important;
	display: inline-block;

	/* fonts icons */
	-webkit-font-smoothing: antialiased;
	-moz-osx-font-smoothing: grayscale;
	vertical-align: top;

	flex-shrink: 0; /* fix for https://github.com/microsoft/vscode/issues/13787 */
}

.monaco-icon-label-container.disabled {
	color: var(--vscode-disabledForeground);
}
.monaco-icon-label > .monaco-icon-label-container {
	min-width: 0;
	overflow: hidden;
	text-overflow: ellipsis;
	flex: 1;
}

.monaco-icon-label > .monaco-icon-label-container > .monaco-icon-name-container > .label-name {
	color: inherit;
	white-space: pre; /* enable to show labels that include multiple whitespaces */
}

.monaco-icon-label > .monaco-icon-label-container > .monaco-icon-name-container > .label-name > .label-separator {
	margin: 0 2px;
	opacity: 0.5;
}

.monaco-icon-label > .monaco-icon-label-container > .monaco-icon-suffix-container > .label-suffix {
	opacity: .7;
	white-space: pre;
}

.monaco-icon-label > .monaco-icon-label-container > .monaco-icon-description-container > .label-description {
	opacity: .7;
	margin-left: 0.5em;
	font-size: 0.9em;
	white-space: pre; /* enable to show labels that include multiple whitespaces */
}

.monaco-icon-label.nowrap > .monaco-icon-label-container > .monaco-icon-description-container > .label-description{
	white-space: nowrap
}

.vs .monaco-icon-label > .monaco-icon-label-container > .monaco-icon-description-container > .label-description {
	opacity: .95;
}

.monaco-icon-label.italic > .monaco-icon-label-container > .monaco-icon-name-container > .label-name,
.monaco-icon-label.italic > .monaco-icon-label-container > .monaco-icon-description-container > .label-description {
	font-style: italic;
}

.monaco-icon-label.deprecated {
	text-decoration: line-through;
	opacity: 0.66;
}

/* make sure apply italic font style to decorations as well */
.monaco-icon-label.italic::after {
	font-style: italic;
}

.monaco-icon-label.strikethrough > .monaco-icon-label-container > .monaco-icon-name-container > .label-name,
.monaco-icon-label.strikethrough > .monaco-icon-label-container > .monaco-icon-description-container > .label-description {
	text-decoration: line-through;
}

.monaco-icon-label::after {
	opacity: 0.75;
	font-size: 90%;
	font-weight: 600;
	margin: auto 16px 0 5px; /* https://github.com/microsoft/vscode/issues/113223 */
	text-align: center;
}

/* make sure selection color wins when a label is being selected */
.monaco-list:focus .selected .monaco-icon-label, /* list */
.monaco-list:focus .selected .monaco-icon-label::after
{
	color: inherit !important;
}

.monaco-list-row.focused.selected .label-description,
.monaco-list-row.selected .label-description {
	opacity: .8;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/iconLabel/iconlabel.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F,qCAAqC;;AAErC;CACC,aAAa,EAAE,4CAA4C;CAC3D,gBAAgB;CAChB,uBAAuB;AACxB;;AAEA;;CAEC,2CAA2C;CAC3C,qBAAqB;CACrB,gCAAgC;CAChC,4BAA4B;CAC5B,kBAAkB;CAClB,WAAW;CACX,YAAY;CACZ,+BAA+B;CAC/B,qBAAqB;;CAErB,gBAAgB;CAChB,mCAAmC;CACnC,kCAAkC;CAClC,mBAAmB;;CAEnB,cAAc,EAAE,6DAA6D;AAC9E;;AAEA;CACC,uCAAuC;AACxC;AACA;CACC,YAAY;CACZ,gBAAgB;CAChB,uBAAuB;CACvB,OAAO;AACR;;AAEA;CACC,cAAc;CACd,gBAAgB,EAAE,4DAA4D;AAC/E;;AAEA;CACC,aAAa;CACb,YAAY;AACb;;AAEA;CACC,WAAW;CACX,gBAAgB;AACjB;;AAEA;CACC,WAAW;CACX,kBAAkB;CAClB,gBAAgB;CAChB,gBAAgB,EAAE,4DAA4D;AAC/E;;AAEA;CACC;AACD;;AAEA;CACC,YAAY;AACb;;AAEA;;CAEC,kBAAkB;AACnB;;AAEA;CACC,6BAA6B;CAC7B,aAAa;AACd;;AAEA,6DAA6D;AAC7D;CACC,kBAAkB;AACnB;;AAEA;;CAEC,6BAA6B;AAC9B;;AAEA;CACC,aAAa;CACb,cAAc;CACd,gBAAgB;CAChB,uBAAuB,EAAE,sDAAsD;CAC/E,kBAAkB;AACnB;;AAEA,kEAAkE;AAClE;;;CAGC,yBAAyB;AAC1B;;AAEA;;CAEC,WAAW;AACZ",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n/* ---------- Icon label ---------- */\n\n.monaco-icon-label {\n	display: flex; /* required for icons support :before rule */\n	overflow: hidden;\n	text-overflow: ellipsis;\n}\n\n.monaco-icon-label::before {\n\n	/* svg icons rendered as background image */\n	background-size: 16px;\n	background-position: left center;\n	background-repeat: no-repeat;\n	padding-right: 6px;\n	width: 16px;\n	height: 22px;\n	line-height: inherit !important;\n	display: inline-block;\n\n	/* fonts icons */\n	-webkit-font-smoothing: antialiased;\n	-moz-osx-font-smoothing: grayscale;\n	vertical-align: top;\n\n	flex-shrink: 0; /* fix for https://github.com/microsoft/vscode/issues/13787 */\n}\n\n.monaco-icon-label-container.disabled {\n	color: var(--vscode-disabledForeground);\n}\n.monaco-icon-label > .monaco-icon-label-container {\n	min-width: 0;\n	overflow: hidden;\n	text-overflow: ellipsis;\n	flex: 1;\n}\n\n.monaco-icon-label > .monaco-icon-label-container > .monaco-icon-name-container > .label-name {\n	color: inherit;\n	white-space: pre; /* enable to show labels that include multiple whitespaces */\n}\n\n.monaco-icon-label > .monaco-icon-label-container > .monaco-icon-name-container > .label-name > .label-separator {\n	margin: 0 2px;\n	opacity: 0.5;\n}\n\n.monaco-icon-label > .monaco-icon-label-container > .monaco-icon-suffix-container > .label-suffix {\n	opacity: .7;\n	white-space: pre;\n}\n\n.monaco-icon-label > .monaco-icon-label-container > .monaco-icon-description-container > .label-description {\n	opacity: .7;\n	margin-left: 0.5em;\n	font-size: 0.9em;\n	white-space: pre; /* enable to show labels that include multiple whitespaces */\n}\n\n.monaco-icon-label.nowrap > .monaco-icon-label-container > .monaco-icon-description-container > .label-description{\n	white-space: nowrap\n}\n\n.vs .monaco-icon-label > .monaco-icon-label-container > .monaco-icon-description-container > .label-description {\n	opacity: .95;\n}\n\n.monaco-icon-label.italic > .monaco-icon-label-container > .monaco-icon-name-container > .label-name,\n.monaco-icon-label.italic > .monaco-icon-label-container > .monaco-icon-description-container > .label-description {\n	font-style: italic;\n}\n\n.monaco-icon-label.deprecated {\n	text-decoration: line-through;\n	opacity: 0.66;\n}\n\n/* make sure apply italic font style to decorations as well */\n.monaco-icon-label.italic::after {\n	font-style: italic;\n}\n\n.monaco-icon-label.strikethrough > .monaco-icon-label-container > .monaco-icon-name-container > .label-name,\n.monaco-icon-label.strikethrough > .monaco-icon-label-container > .monaco-icon-description-container > .label-description {\n	text-decoration: line-through;\n}\n\n.monaco-icon-label::after {\n	opacity: 0.75;\n	font-size: 90%;\n	font-weight: 600;\n	margin: auto 16px 0 5px; /* https://github.com/microsoft/vscode/issues/113223 */\n	text-align: center;\n}\n\n/* make sure selection color wins when a label is being selected */\n.monaco-list:focus .selected .monaco-icon-label, /* list */\n.monaco-list:focus .selected .monaco-icon-label::after\n{\n	color: inherit !important;\n}\n\n.monaco-list-row.focused.selected .label-description,\n.monaco-list-row.selected .label-description {\n	opacity: .8;\n}\n"],sourceRoot:""}]),n.d(t,{},{A:a})},1366(e,t,n){var o=n(571354),i=n.n(o),s=n(576314),a=n.n(s)()(i());a.push([e.id,`/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

.monaco-inputbox {
	position: relative;
	display: block;
	padding: 0;
	box-sizing:	border-box;
	border-radius: 2px;

	/* Customizable */
	font-size: inherit;
}

.monaco-inputbox > .ibwrapper > .input,
.monaco-inputbox > .ibwrapper > .mirror {

	/* Customizable */
	padding: 4px 6px;
}

.monaco-inputbox > .ibwrapper {
	position: relative;
	width: 100%;
	height: 100%;
}

.monaco-inputbox > .ibwrapper > .input {
	display: inline-block;
	box-sizing:	border-box;
	width: 100%;
	height: 100%;
	line-height: inherit;
	border: none;
	font-family: inherit;
	font-size: inherit;
	resize: none;
	color: inherit;
}

.monaco-inputbox > .ibwrapper > input {
	text-overflow: ellipsis;
}

.monaco-inputbox > .ibwrapper > textarea.input {
	display: block;
	scrollbar-width: none; /* Firefox: hide scrollbars */
	outline: none;
}

.monaco-inputbox > .ibwrapper > textarea.input::-webkit-scrollbar {
	display: none; /* Chrome + Safari: hide scrollbar */
}

.monaco-inputbox > .ibwrapper > textarea.input.empty {
	white-space: nowrap;
}

.monaco-inputbox > .ibwrapper > .mirror {
	position: absolute;
	display: inline-block;
	width: 100%;
	top: 0;
	left: 0;
	box-sizing: border-box;
	white-space: pre-wrap;
	visibility: hidden;
	word-wrap: break-word;
}

/* Context view */

.monaco-inputbox-container {
	text-align: right;
}

.monaco-inputbox-container .monaco-inputbox-message {
	display: inline-block;
	overflow: hidden;
	text-align: left;
	width: 100%;
	box-sizing:	border-box;
	padding: 0.4em;
	font-size: 12px;
	line-height: 17px;
	margin-top: -1px;
	word-wrap: break-word;
}

/* Action bar support */
.monaco-inputbox .monaco-action-bar {
	position: absolute;
	right: 2px;
	top: 4px;
}

.monaco-inputbox .monaco-action-bar .action-item {
	margin-left: 2px;
}

.monaco-inputbox .monaco-action-bar .action-item .codicon {
	background-repeat: no-repeat;
	width: 16px;
	height: 16px;
}
`,"",{version:3,sources:["webpack://./node_modules/monaco-editor/esm/vs/base/browser/ui/inputbox/inputBox.css"],names:[],mappings:"AAAA;;;+FAG+F;;AAE/F;CACC,kBAAkB;CAClB,cAAc;CACd,UAAU;CACV,sBAAsB;CACtB,kBAAkB;;CAElB,iBAAiB;CACjB,kBAAkB;AACnB;;AAEA;;;CAGC,iBAAiB;CACjB,gBAAgB;AACjB;;AAEA;CACC,kBAAkB;CAClB,WAAW;CACX,YAAY;AACb;;AAEA;CACC,qBAAqB;CACrB,sBAAsB;CACtB,WAAW;CACX,YAAY;CACZ,oBAAoB;CACpB,YAAY;CACZ,oBAAoB;CACpB,kBAAkB;CAClB,YAAY;CACZ,cAAc;AACf;;AAEA;CACC,uBAAuB;AACxB;;AAEA;CACC,cAAc;CACd,qBAAqB,EAAE,6BAA6B;CACpD,aAAa;AACd;;AAEA;CACC,aAAa,EAAE,oCAAoC;AACpD;;AAEA;CACC,mBAAmB;AACpB;;AAEA;CACC,kBAAkB;CAClB,qBAAqB;CACrB,WAAW;CACX,MAAM;CACN,OAAO;CACP,sBAAsB;CACtB,qBAAqB;CACrB,kBAAkB;CAClB,qBAAqB;AACtB;;AAEA,iBAAiB;;AAEjB;CACC,iBAAiB;AAClB;;AAEA;CACC,qBAAqB;CACrB,gBAAgB;CAChB,gBAAgB;CAChB,WAAW;CACX,sBAAsB;CACtB,cAAc;CACd,eAAe;CACf,iBAAiB;CACjB,gBAAgB;CAChB,qBAAqB;AACtB;;AAEA,uBAAuB;AACvB;CACC,kBAAkB;CAClB,UAAU;CACV,QAAQ;AACT;;AAEA;CACC,gBAAgB;AACjB;;AAEA;CACC,4BAA4B;CAC5B,WAAW;CACX,YAAY;AACb",sourcesContent:["/*---------------------------------------------------------------------------------------------\n *  Copyright (c) Microsoft Corporation. All rights reserved.\n *  Licensed under the MIT License. See License.txt in the project root for license information.\n *--------------------------------------------------------------------------------------------*/\n\n.monaco-inputbox {\n	position: relative;\n	display: block;\n	padding: 0;\n	box-sizing:	border-box;\n	border-radius: 2px;\n\n	/* Customizable */\n	font-size: inherit;\n}\n\n.monaco-inputbox > .ibwrapper > .input,\n.monaco-inputbox > .ibwrapper > .mirror {\n\n	/* Customizable */\n	padding: 4px 6px;\n}\n\n.monaco-inputbox > .ibwrapper {\n	position: relative;\n	width: 100%;\n	height: 100%;\n}\n\n.monaco-inputbox > .ibwrapper > .input {\n	display: inline-block;\n	box-sizing:	border-box;\n	width: 100%;\n	height: 100%;\n	line-height: inherit;\n	border: none;\n	font-family: inherit;\n	font-size: inherit;\n	resize: none;\n	color: inherit;\n}\n\n.monaco-inputbox > .ibwrapper > input {\n	text-overflow: ellipsis;\n}\n\n.monaco-inputbox > .ibwrapper > textarea.input {\n	display: block;\n	scrollbar-width: none; /* Firefox: hide scrollbars */\n	outline: none;\n}\n\n.monaco-inputbox > .ibwrapper > textarea.input::-webkit-scrollbar {\n	display: none; /* Chrome + Safari: hide scrollbar */\n}\n\n.monaco-inputbox > .ibwrapper > textarea.input.empty {\n	white-space: nowrap;\n}\n\n.monaco-inputbox > .ibwrapper > .mirror {\n	position: absolute;\n	display: inline-block;\n	width: 100%;\n	top: 0;\n	left: 0;\n	box-sizing: border-box;\n	white-space: pre-wrap;\n	visibility: hidden;\n	word-wrap: break-word;\n}\n\n/* Context view */\n\n.monaco-inputbox-container {\n	text-align: right;\n}\n\n.monaco-inputbox-container .monaco-inputbox-message {\n	display: inline-block;\n	overflow: hidden;\n	text-align: left;\n	width: 100%;\n	box-sizing:	border-box;\n	padding: 0.4em;\n	font-size: 12px;\n	line-height: 17px;\n	margin-top: -1px;\n	word-wrap: break-word;\n}\n\n/* Action bar support */\n.monaco-inputbox .monaco-action-bar {\n	position: absolute;\n	right: 2px;\n	top: 4px;\n}\n\n.monaco-inputbox .monaco-action-bar .action-item {\n	margin-left: 2px;\n}\n\n.monaco-inputbox .monaco-action-bar .action-item .codicon {\n	background-repeat: no-repeat;\n	width: 16px;\n	height: 16px;\n}\n"],sourceRoot:""}]),n.d(t,{},{A:a})},373956(e,t,n){var o=n(555893),i=n(847529),s=n(263339);class a{constructor(e,t){this.timestamp=Date.now(),this.browserEvent=t,this.leftButton=0===t.button,this.middleButton=1===t.button,this.rightButton=2===t.button,this.buttons=t.buttons,this.target=t.target,this.detail=t.detail||1,"dblclick"===t.type&&(this.detail=2),this.ctrlKey=t.ctrlKey,this.shiftKey=t.shiftKey,this.altKey=t.altKey,this.metaKey=t.metaKey,"number"==typeof t.pageX?(this.posx=t.pageX,this.posy=t.pageY):(this.posx=t.clientX+this.target.ownerDocument.body.scrollLeft+this.target.ownerDocument.documentElement.scrollLeft,this.posy=t.clientY+this.target.ownerDocument.body.scrollTop+this.target.ownerDocument.documentElement.scrollTop);const n=i.Q.getPositionOfChildWindowRelativeToAncestorWindow(e,t.view);this.posx-=n.left,this.posy-=n.top}preventDefault(){this.browserEvent.preventDefault()}stopPropagation(){this.browserEvent.stopPropagation()}}class r{constructor(e,t=0,n=0){var i;this.browserEvent=e||null,this.target=e?e.target||e.targetNode||e.srcElement:null,this.deltaY=n,this.deltaX=t;let a=!1;if(o.H8){const e=navigator.userAgent.match(/Chrome\/(\d+)/);a=(e?parseInt(e[1]):123)<=122}if(e){const t=(null==(i=e.view)?void 0:i.devicePixelRatio)||1;void 0!==e.wheelDeltaY?a?this.deltaY=e.wheelDeltaY/(120*t):this.deltaY=e.wheelDeltaY/120:void 0!==e.VERTICAL_AXIS&&e.axis===e.VERTICAL_AXIS?this.deltaY=-e.detail/3:"wheel"===e.type&&(e.deltaMode===e.DOM_DELTA_LINE?o.gm&&!s.zx?this.deltaY=-e.deltaY/3:this.deltaY=-e.deltaY:this.deltaY=-e.deltaY/40),void 0!==e.wheelDeltaX?o.nr&&s.uF?this.deltaX=-(e.wheelDeltaX/120):a?this.deltaX=e.wheelDeltaX/(120*t):this.deltaX=e.wheelDeltaX/120:void 0!==e.HORIZONTAL_AXIS&&e.axis===e.HORIZONTAL_AXIS?this.deltaX=-e.detail/3:"wheel"===e.type&&(e.deltaMode===e.DOM_DELTA_LINE?o.gm&&!s.zx?this.deltaX=-e.deltaX/3:this.deltaX=-e.deltaX:this.deltaX=-e.deltaX/40),0===this.deltaY&&0===this.deltaX&&e.wheelDelta&&(a?this.deltaY=e.wheelDelta/(120*t):this.deltaY=e.wheelDelta/120)}}preventDefault(){var e;null==(e=this.browserEvent)||e.preventDefault()}stopPropagation(){var e;null==(e=this.browserEvent)||e.stopPropagation()}}n.d(t,{$:()=>r,P:()=>a})},542863(e,t,n){var o;!function(e){let t={total:0,min:Number.MAX_VALUE,max:0},n={...t},o={...t},i={...t},s=0,a={keydown:0,input:0,render:0};function r(){1===a.keydown&&(performance.mark("keydown/end"),a.keydown=2)}function l(){performance.mark("input/start"),a.input=1,d()}function c(){1===a.input&&(performance.mark("input/end"),a.input=2)}function h(){1===a.render&&(performance.mark("render/end"),a.render=2)}function d(){setTimeout(u)}function u(){2===a.keydown&&2===a.input&&2===a.render&&(performance.mark("inputlatency/end"),performance.measure("keydown","keydown/start","keydown/end"),performance.measure("input","input/start","input/end"),performance.measure("render","render/start","render/end"),performance.measure("inputlatency","inputlatency/start","inputlatency/end"),A("keydown",t),A("input",n),A("render",o),A("inputlatency",i),s++,performance.clearMarks("keydown/start"),performance.clearMarks("keydown/end"),performance.clearMarks("input/start"),performance.clearMarks("input/end"),performance.clearMarks("render/start"),performance.clearMarks("render/end"),performance.clearMarks("inputlatency/start"),performance.clearMarks("inputlatency/end"),performance.clearMeasures("keydown"),performance.clearMeasures("input"),performance.clearMeasures("render"),performance.clearMeasures("inputlatency"),a.keydown=0,a.input=0,a.render=0)}function A(e,t){let n=performance.getEntriesByName(e)[0].duration;t.total+=n,t.min=Math.min(t.min,n),t.max=Math.max(t.max,n)}function p(e){return{average:e.total/s,max:e.max,min:e.min}}function m(e){e.total=0,e.min=Number.MAX_VALUE,e.max=0}e.onKeyDown=function(){u(),performance.mark("inputlatency/start"),performance.mark("keydown/start"),a.keydown=1,queueMicrotask(r)},e.onBeforeInput=l,e.onInput=function(){0===a.input&&l(),queueMicrotask(c)},e.onKeyUp=function(){u()},e.onSelectionChange=function(){u()},e.onRenderStart=function(){2===a.keydown&&2===a.input&&0===a.render&&(performance.mark("render/start"),a.render=1,queueMicrotask(h),d())},e.getAndClearMeasurements=function(){if(0===s)return;let e={keydown:p(t),input:p(n),render:p(o),total:p(i),sampleCount:s};return m(t),m(n),m(o),m(i),s=0,e}}(o||(o={})),n.d(t,{p:()=>o})},904770(e,t,n){var o=n(614333),i=n(2106),s=n(310998);class a extends s.jG{constructor(e){super(),this._onDidChange=this._register(new i.vl),this.onDidChange=this._onDidChange.event,this._listener=()=>this._handleChange(e,!0),this._mediaQueryList=null,this._handleChange(e,!1)}_handleChange(e,t){var n;null==(n=this._mediaQueryList)||n.removeEventListener("change",this._listener),this._mediaQueryList=e.matchMedia(`(resolution: ${e.devicePixelRatio}dppx)`),this._mediaQueryList.addEventListener("change",this._listener),t&&this._onDidChange.fire()}}class r extends s.jG{get value(){return this._value}constructor(e){super(),this._onDidChange=this._register(new i.vl),this.onDidChange=this._onDidChange.event,this._value=this._getPixelRatio(e);const t=this._register(new a(e));this._register(t.onDidChange(()=>{this._value=this._getPixelRatio(e),this._onDidChange.fire(this._value)}))}_getPixelRatio(e){let t=document.createElement("canvas").getContext("2d");return(e.devicePixelRatio||1)/(t.webkitBackingStorePixelRatio||t.mozBackingStorePixelRatio||t.msBackingStorePixelRatio||t.oBackingStorePixelRatio||t.backingStorePixelRatio||1)}}let l=new class{constructor(){this.mapWindowIdToPixelRatioMonitor=new Map}_getOrCreatePixelRatioMonitor(e){let t=(0,o.Q2)(e),n=this.mapWindowIdToPixelRatioMonitor.get(t);return n||(n=(0,s.lC)(new r(e)),this.mapWindowIdToPixelRatioMonitor.set(t,n),(0,s.lC)(i.Jh.once(o.Fv)(({vscodeWindowId:e})=>{e===t&&(null==n||n.dispose(),this.mapWindowIdToPixelRatioMonitor.delete(t))}))),n}getInstance(e){return this._getOrCreatePixelRatioMonitor(e)}};n.d(t,{},{c:l})},830474(e,t,n){var o,i,s=n(614333),a=n(348877),r=n(413338),l=n(988846),c=n(2106),h=n(310998),d=n(285525);(o=i||(i={})).Tap="-monaco-gesturetap",o.Change="-monaco-gesturechange",o.Start="-monaco-gesturestart",o.End="-monaco-gesturesend",o.Contextmenu="-monaco-gesturecontextmenu";class u extends h.jG{constructor(){super(),this.dispatched=!1,this.targets=new d.w,this.ignoreTargets=new d.w,this.activeTouches={},this.handle=null,this._lastSetTapCountTime=0,this._register(c.Jh.runAndSubscribe(s.Iv,({window:e,disposables:t})=>{t.add(s.ko(e.document,"touchstart",e=>this.onTouchStart(e),{passive:!1})),t.add(s.ko(e.document,"touchend",t=>this.onTouchEnd(e,t))),t.add(s.ko(e.document,"touchmove",e=>this.onTouchMove(e),{passive:!1}))},{window:a.G,disposables:this._store}))}static addTarget(e){if(!u.isTouchDevice())return h.jG.None;u.INSTANCE||(u.INSTANCE=(0,h.lC)(new u));let t=u.INSTANCE.targets.push(e);return(0,h.s)(t)}static ignoreTarget(e){if(!u.isTouchDevice())return h.jG.None;u.INSTANCE||(u.INSTANCE=(0,h.lC)(new u));let t=u.INSTANCE.ignoreTargets.push(e);return(0,h.s)(t)}static isTouchDevice(){return"ontouchstart"in a.G||navigator.maxTouchPoints>0}dispose(){this.handle&&(this.handle.dispose(),this.handle=null),super.dispose()}onTouchStart(e){let t=Date.now();this.handle&&(this.handle.dispose(),this.handle=null);for(let n=0,o=e.targetTouches.length;n<o;n++){let o=e.targetTouches.item(n);this.activeTouches[o.identifier]={id:o.identifier,initialTarget:o.target,initialTimeStamp:t,initialPageX:o.pageX,initialPageY:o.pageY,rollingTimestamps:[t],rollingPageX:[o.pageX],rollingPageY:[o.pageY]};let s=this.newGestureEvent(i.Start,o.target);s.pageX=o.pageX,s.pageY=o.pageY,this.dispatchEvent(s)}this.dispatched&&(e.preventDefault(),e.stopPropagation(),this.dispatched=!1)}onTouchEnd(e,t){let n=Date.now(),o=Object.keys(this.activeTouches).length;for(let s=0,a=t.changedTouches.length;s<a;s++){let a=t.changedTouches.item(s);if(!this.activeTouches.hasOwnProperty(String(a.identifier))){console.warn("move of an UNKNOWN touch",a);continue}let l=this.activeTouches[a.identifier],c=Date.now()-l.initialTimeStamp;if(c<u.HOLD_DELAY&&30>Math.abs(l.initialPageX-r.RT(l.rollingPageX))&&30>Math.abs(l.initialPageY-r.RT(l.rollingPageY))){let e=this.newGestureEvent(i.Tap,l.initialTarget);e.pageX=r.RT(l.rollingPageX),e.pageY=r.RT(l.rollingPageY),this.dispatchEvent(e)}else if(c>=u.HOLD_DELAY&&30>Math.abs(l.initialPageX-r.RT(l.rollingPageX))&&30>Math.abs(l.initialPageY-r.RT(l.rollingPageY))){let e=this.newGestureEvent(i.Contextmenu,l.initialTarget);e.pageX=r.RT(l.rollingPageX),e.pageY=r.RT(l.rollingPageY),this.dispatchEvent(e)}else if(1===o){let t=r.RT(l.rollingPageX),o=r.RT(l.rollingPageY),i=r.RT(l.rollingTimestamps)-l.rollingTimestamps[0],s=t-l.rollingPageX[0],a=o-l.rollingPageY[0],c=[...this.targets].filter(e=>l.initialTarget instanceof Node&&e.contains(l.initialTarget));this.inertia(e,c,n,Math.abs(s)/i,s>0?1:-1,t,Math.abs(a)/i,a>0?1:-1,o)}this.dispatchEvent(this.newGestureEvent(i.End,l.initialTarget)),delete this.activeTouches[a.identifier]}this.dispatched&&(t.preventDefault(),t.stopPropagation(),this.dispatched=!1)}newGestureEvent(e,t){let n=document.createEvent("CustomEvent");return n.initEvent(e,!1,!0),n.initialTarget=t,n.tapCount=0,n}dispatchEvent(e){if(e.type===i.Tap){let t=new Date().getTime(),n=0;n=t-this._lastSetTapCountTime>u.CLEAR_TAP_COUNT_TIME?1:2,this._lastSetTapCountTime=t,e.tapCount=n}else(e.type===i.Change||e.type===i.Contextmenu)&&(this._lastSetTapCountTime=0);if(e.initialTarget instanceof Node){for(let t of this.ignoreTargets)if(t.contains(e.initialTarget))return;let t=[];for(let n of this.targets)if(n.contains(e.initialTarget)){let o=0,i=e.initialTarget;for(;i&&i!==n;)o++,i=i.parentElement;t.push([o,n])}for(let[n,o]of(t.sort((e,t)=>e[0]-t[0]),t))o.dispatchEvent(e),this.dispatched=!0}}inertia(e,t,n,o,a,r,l,c,h){this.handle=s.PG(e,()=>{let s=Date.now(),d=s-n,A=0,p=0,m=!0;o+=u.SCROLL_FRICTION*d,l+=u.SCROLL_FRICTION*d,o>0&&(m=!1,A=a*o*d),l>0&&(m=!1,p=c*l*d);let g=this.newGestureEvent(i.Change);g.translationX=A,g.translationY=p,t.forEach(e=>e.dispatchEvent(g)),m||this.inertia(e,t,s,o,a,r+A,l,c,h+p)})}onTouchMove(e){let t=Date.now();for(let n=0,o=e.changedTouches.length;n<o;n++){let o=e.changedTouches.item(n);if(!this.activeTouches.hasOwnProperty(String(o.identifier))){console.warn("end of an UNKNOWN touch",o);continue}let s=this.activeTouches[o.identifier],a=this.newGestureEvent(i.Change,s.initialTarget);a.translationX=o.pageX-r.RT(s.rollingPageX),a.translationY=o.pageY-r.RT(s.rollingPageY),a.pageX=o.pageX,a.pageY=o.pageY,this.dispatchEvent(a),s.rollingPageX.length>3&&(s.rollingPageX.shift(),s.rollingPageY.shift(),s.rollingTimestamps.shift()),s.rollingPageX.push(o.pageX),s.rollingPageY.push(o.pageY),s.rollingTimestamps.push(t)}this.dispatched&&(e.preventDefault(),e.stopPropagation(),this.dispatched=!1)}}u.SCROLL_FRICTION=-.005,u.HOLD_DELAY=700,u.CLEAR_TAP_COUNT_TIME=400,function(e,t,n,o){var i,s=arguments.length,a=s<3?t:null===o?o=Object.getOwnPropertyDescriptor(t,n):o;if("object"==typeof Reflect&&"function"==typeof Reflect.decorate)a=Reflect.decorate(e,t,n,o);else for(var r=e.length-1;r>=0;r--)(i=e[r])&&(a=(s<3?i(a):s>3?i(t,n,a):i(t,n))||a);s>3&&a&&Object.defineProperty(t,n,a)}([l.B],u,"isTouchDevice",null),n.d(t,{B:()=>i,q:()=>u})},813021(e,t,n){var o=n(348877),i=n(494327);function s(e,t){var n;let s=globalThis.MonacoEnvironment;if(null==s?void 0:s.createTrustedTypesPolicy)try{return s.createTrustedTypesPolicy(e,t)}catch(e){(0,i.dz)(e);return}try{return null==(n=o.G.trustedTypes)?void 0:n.createPolicy(e,t)}catch(e){(0,i.dz)(e);return}}n.d(t,{H:()=>s})},223473(e,t,n){var o=n(555893),i=n(939587),s=n(614333),a=n(830474),r=n(165568),l=n(182622),c=n(427969),h=n(310998),d=n(263339),u=n(779359);n(896861);var A=n(3765),p=n(720396);class m extends h.jG{get action(){return this._action}constructor(e,t,n={}){super(),this.options=n,this._context=e||this,this._action=t,t instanceof c.rc&&this._register(t.onDidChange(e=>{this.element&&this.handleActionChangeEvent(e)}))}handleActionChangeEvent(e){void 0!==e.enabled&&this.updateEnabled(),void 0!==e.checked&&this.updateChecked(),void 0!==e.class&&this.updateClass(),void 0!==e.label&&(this.updateLabel(),this.updateTooltip()),void 0!==e.tooltip&&this.updateTooltip()}get actionRunner(){return this._actionRunner||(this._actionRunner=this._register(new c.LN)),this._actionRunner}set actionRunner(e){this._actionRunner=e}isEnabled(){return this._action.enabled}setActionContext(e){this._context=e}render(e){let t=this.element=e;this._register(a.q.addTarget(e));let n=this.options&&this.options.draggable;n&&(e.draggable=!0,o.gm&&this._register((0,s.ko)(e,s.Bx.DRAG_START,e=>{var t;return null==(t=e.dataTransfer)?void 0:t.setData(i.t.TEXT,this._action.label)}))),this._register((0,s.ko)(t,a.B.Tap,e=>this.onClick(e,!0))),this._register((0,s.ko)(t,s.Bx.MOUSE_DOWN,e=>{n||s.fs.stop(e,!0),this._action.enabled&&0===e.button&&t.classList.add("active")})),d.zx&&this._register((0,s.ko)(t,s.Bx.CONTEXT_MENU,e=>{0===e.button&&!0===e.ctrlKey&&this.onClick(e)})),this._register((0,s.ko)(t,s.Bx.CLICK,e=>{s.fs.stop(e,!0),this.options&&this.options.isMenu||this.onClick(e)})),this._register((0,s.ko)(t,s.Bx.DBLCLICK,e=>{s.fs.stop(e,!0)})),[s.Bx.MOUSE_UP,s.Bx.MOUSE_OUT].forEach(e=>{this._register((0,s.ko)(t,e,e=>{s.fs.stop(e),t.classList.remove("active")}))})}onClick(e,t=!1){var n;s.fs.stop(e,!0);let o=u.z(this._context)?(null==(n=this.options)?void 0:n.useEventAsContext)?e:{preserveFocus:t}:this._context;this.actionRunner.run(this._action,o)}focus(){this.element&&(this.element.tabIndex=0,this.element.focus(),this.element.classList.add("focused"))}blur(){this.element&&(this.element.blur(),this.element.tabIndex=-1,this.element.classList.remove("focused"))}setFocusable(e){this.element&&(this.element.tabIndex=e?0:-1)}get trapsArrowNavigation(){return!1}updateEnabled(){}updateLabel(){}getClass(){return this.action.class}getTooltip(){return this.action.tooltip}updateTooltip(){var e,t,n;if(!this.element)return;let o=null!=(e=this.getTooltip())?e:"";if(this.updateAriaLabel(),null==(t=this.options.hoverDelegate)?void 0:t.showNativeHover)this.element.title=o;else if(this.customHover||""===o)this.customHover&&this.customHover.update(o);else{let e=null!=(n=this.options.hoverDelegate)?n:(0,r.nZ)("element");this.customHover=this._store.add((0,p.i)().setupUpdatableHover(e,this.element,o))}}updateAriaLabel(){var e;if(this.element){let t=null!=(e=this.getTooltip())?e:"";this.element.setAttribute("aria-label",t)}}updateClass(){}updateChecked(){}dispose(){this.element&&(this.element.remove(),this.element=void 0),this._context=void 0,super.dispose()}}class g extends m{constructor(e,t,n){super(e,t,n),this.options=n,this.options.icon=void 0!==n.icon&&n.icon,this.options.label=void 0===n.label||n.label,this.cssClass=""}render(e){super.render(e),u.j(this.element);let t=document.createElement("a");if(t.classList.add("action-label"),t.setAttribute("role",this.getDefaultAriaRole()),this.label=t,this.element.appendChild(t),this.options.label&&this.options.keybinding){let e=document.createElement("span");e.classList.add("keybinding"),e.textContent=this.options.keybinding,this.element.appendChild(e)}this.updateClass(),this.updateLabel(),this.updateTooltip(),this.updateEnabled(),this.updateChecked()}getDefaultAriaRole(){return this._action.id===c.wv.ID?"presentation":this.options.isMenu?"menuitem":"button"}focus(){this.label&&(this.label.tabIndex=0,this.label.focus())}blur(){this.label&&(this.label.tabIndex=-1)}setFocusable(e){this.label&&(this.label.tabIndex=e?0:-1)}updateLabel(){this.options.label&&this.label&&(this.label.textContent=this.action.label)}getTooltip(){let e=null;return this.action.tooltip?e=this.action.tooltip:!this.options.label&&this.action.label&&this.options.icon&&(e=this.action.label,this.options.keybinding&&(e=A.kg({key:"titleLabel",comment:["action title","action keybinding"]},"{0} ({1})",e,this.options.keybinding))),null!=e?e:void 0}updateClass(){var e;this.cssClass&&this.label&&this.label.classList.remove(...this.cssClass.split(" ")),this.options.icon?(this.cssClass=this.getClass(),this.label&&(this.label.classList.add("codicon"),this.cssClass&&this.label.classList.add(...this.cssClass.split(" "))),this.updateEnabled()):null==(e=this.label)||e.classList.remove("codicon")}updateEnabled(){var e,t;this.action.enabled?(this.label&&(this.label.removeAttribute("aria-disabled"),this.label.classList.remove("disabled")),null==(e=this.element)||e.classList.remove("disabled")):(this.label&&(this.label.setAttribute("aria-disabled","true"),this.label.classList.add("disabled")),null==(t=this.element)||t.classList.add("disabled"))}updateAriaLabel(){var e;if(this.label){let t=null!=(e=this.getTooltip())?e:"";this.label.setAttribute("aria-label",t)}}updateChecked(){this.label&&(void 0!==this.action.checked?(this.label.classList.toggle("checked",this.action.checked),this.label.setAttribute("aria-checked",this.action.checked?"true":"false"),this.label.setAttribute("role","checkbox")):(this.label.classList.remove("checked"),this.label.removeAttribute("aria-checked"),this.label.setAttribute("role",this.getDefaultAriaRole())))}}class C extends m{constructor(e,t,n,o,i,s,a){super(e,t),this.selectBox=new l.a(n,o,i,s,a),this.selectBox.setFocusable(!1),this._register(this.selectBox),this.registerListeners()}select(e){this.selectBox.select(e)}registerListeners(){this._register(this.selectBox.onDidSelect(e=>this.runAction(e.selected,e.index)))}runAction(e,t){this.actionRunner.run(this._action,this.getActionContext(e,t))}getActionContext(e,t){return e}setFocusable(e){this.selectBox.setFocusable(e)}focus(){var e;null==(e=this.selectBox)||e.focus()}blur(){var e;null==(e=this.selectBox)||e.blur()}render(e){this.selectBox.render(e)}}n.d(t,{EH:()=>m,XF:()=>C,Z4:()=>g})},777439(e,t,n){var o=n(614333),i=n(287594),s=n(223473),a=n(165568),r=n(427969),l=n(2106),c=n(310998),h=n(779359);n(896861);class d extends c.jG{constructor(e,t={}){var n,h,d,u,A,p,m;let g,C;switch(super(),this._actionRunnerDisposables=this._register(new c.Cm),this.viewItemDisposables=this._register(new c.$w),this.triggerKeyDown=!1,this.focusable=!0,this._onDidBlur=this._register(new l.vl),this.onDidBlur=this._onDidBlur.event,this._onDidCancel=this._register(new l.vl({onWillAddFirstListener:()=>this.cancelHasListener=!0})),this.onDidCancel=this._onDidCancel.event,this.cancelHasListener=!1,this._onDidRun=this._register(new l.vl),this.onDidRun=this._onDidRun.event,this._onWillRun=this._register(new l.vl),this.onWillRun=this._onWillRun.event,this.options=t,this._context=null!=(n=t.context)?n:null,this._orientation=null!=(h=this.options.orientation)?h:0,this._triggerKeys={keyDown:null!=(u=null==(d=this.options.triggerKeys)?void 0:d.keyDown)&&u,keys:null!=(p=null==(A=this.options.triggerKeys)?void 0:A.keys)?p:[3,10]},this._hoverDelegate=null!=(m=t.hoverDelegate)?m:this._register((0,a.bW)()),this.options.actionRunner?this._actionRunner=this.options.actionRunner:(this._actionRunner=new r.LN,this._actionRunnerDisposables.add(this._actionRunner)),this._actionRunnerDisposables.add(this._actionRunner.onDidRun(e=>this._onDidRun.fire(e))),this._actionRunnerDisposables.add(this._actionRunner.onWillRun(e=>this._onWillRun.fire(e))),this.viewItems=[],this.focusedItem=void 0,this.domNode=document.createElement("div"),this.domNode.className="monaco-action-bar",this._orientation){case 0:g=[15],C=[17];break;case 1:g=[16],C=[18],this.domNode.className+=" vertical"}this._register(o.ko(this.domNode,o.Bx.KEY_DOWN,e=>{let t=new i.Z(e),n=!0,o="number"==typeof this.focusedItem?this.viewItems[this.focusedItem]:void 0;g&&(t.equals(g[0])||t.equals(g[1]))?n=this.focusPrevious():C&&(t.equals(C[0])||t.equals(C[1]))?n=this.focusNext():t.equals(9)&&this.cancelHasListener?this._onDidCancel.fire():t.equals(14)?n=this.focusFirst():t.equals(13)?n=this.focusLast():t.equals(2)&&o instanceof s.EH&&o.trapsArrowNavigation?n=this.focusNext():this.isTriggerKeyEvent(t)?this._triggerKeys.keyDown?this.doTrigger(t):this.triggerKeyDown=!0:n=!1,n&&(t.preventDefault(),t.stopPropagation())})),this._register(o.ko(this.domNode,o.Bx.KEY_UP,e=>{let t=new i.Z(e);this.isTriggerKeyEvent(t)?(!this._triggerKeys.keyDown&&this.triggerKeyDown&&(this.triggerKeyDown=!1,this.doTrigger(t)),t.preventDefault(),t.stopPropagation()):(t.equals(2)||t.equals(1026)||t.equals(16)||t.equals(18)||t.equals(15)||t.equals(17))&&this.updateFocusedItem()})),this.focusTracker=this._register(o.w5(this.domNode)),this._register(this.focusTracker.onDidBlur(()=>{o.bq()!==this.domNode&&o.QX(o.bq(),this.domNode)||(this._onDidBlur.fire(),this.previouslyFocusedItem=this.focusedItem,this.focusedItem=void 0,this.triggerKeyDown=!1)})),this._register(this.focusTracker.onDidFocus(()=>this.updateFocusedItem())),this.actionsList=document.createElement("ul"),this.actionsList.className="actions-container",this.options.highlightToggledItems&&this.actionsList.classList.add("highlight-toggled"),this.actionsList.setAttribute("role",this.options.ariaRole||"toolbar"),this.options.ariaLabel&&this.actionsList.setAttribute("aria-label",this.options.ariaLabel),this.domNode.appendChild(this.actionsList),e.appendChild(this.domNode)}refreshRole(){this.length()>=1?this.actionsList.setAttribute("role",this.options.ariaRole||"toolbar"):this.actionsList.setAttribute("role","presentation")}setFocusable(e){if(this.focusable=e,this.focusable){let e=this.viewItems.find(e=>e instanceof s.EH&&e.isEnabled());e instanceof s.EH&&e.setFocusable(!0)}else this.viewItems.forEach(e=>{e instanceof s.EH&&e.setFocusable(!1)})}isTriggerKeyEvent(e){let t=!1;return this._triggerKeys.keys.forEach(n=>{t=t||e.equals(n)}),t}updateFocusedItem(){var e,t;for(let n=0;n<this.actionsList.children.length;n++){let i=this.actionsList.children[n];if(o.QX(o.bq(),i)){this.focusedItem=n,null==(t=null==(e=this.viewItems[this.focusedItem])?void 0:e.showHover)||t.call(e);break}}}get context(){return this._context}set context(e){this._context=e,this.viewItems.forEach(t=>t.setActionContext(e))}get actionRunner(){return this._actionRunner}set actionRunner(e){this._actionRunner=e,this._actionRunnerDisposables.clear(),this._actionRunnerDisposables.add(this._actionRunner.onDidRun(e=>this._onDidRun.fire(e))),this._actionRunnerDisposables.add(this._actionRunner.onWillRun(e=>this._onWillRun.fire(e))),this.viewItems.forEach(t=>t.actionRunner=e)}getContainer(){return this.domNode}getAction(e){var t;if("number"==typeof e)return null==(t=this.viewItems[e])?void 0:t.action;if(e instanceof HTMLElement){for(;e.parentElement!==this.actionsList;){if(!e.parentElement)return;e=e.parentElement}for(let t=0;t<this.actionsList.childNodes.length;t++)if(this.actionsList.childNodes[t]===e)return this.viewItems[t].action}}push(e,t={}){let n=Array.isArray(e)?e:[e],i=h.Et(t.index)?t.index:null;n.forEach(e=>{let n,a=document.createElement("li");a.className="action-item",a.setAttribute("role","presentation");let r={hoverDelegate:this._hoverDelegate,...t};this.options.actionViewItemProvider&&(n=this.options.actionViewItemProvider(e,r)),n||(n=new s.Z4(this.context,e,r)),this.options.allowContextMenu||this.viewItemDisposables.set(n,o.ko(a,o.Bx.CONTEXT_MENU,e=>{o.fs.stop(e,!0)})),n.actionRunner=this._actionRunner,n.setActionContext(this.context),n.render(a),this.focusable&&n instanceof s.EH&&0===this.viewItems.length&&n.setFocusable(!0),null===i||i<0||i>=this.actionsList.children.length?(this.actionsList.appendChild(a),this.viewItems.push(n)):(this.actionsList.insertBefore(a,this.actionsList.children[i]),this.viewItems.splice(i,0,n),i++)}),"number"==typeof this.focusedItem&&this.focus(this.focusedItem),this.refreshRole()}clear(){this.isEmpty()||(this.viewItems=(0,c.AS)(this.viewItems),this.viewItemDisposables.clearAndDisposeAll(),o.w_(this.actionsList),this.refreshRole())}length(){return this.viewItems.length}isEmpty(){return 0===this.viewItems.length}focus(e){let t,n=!1;if(void 0===e?n=!0:"number"==typeof e?t=e:"boolean"==typeof e&&(n=e),n&&void 0===this.focusedItem){let e=this.viewItems.findIndex(e=>e.isEnabled());this.focusedItem=-1===e?void 0:e,this.updateFocus(void 0,void 0,!0)}else void 0!==t&&(this.focusedItem=t),this.updateFocus(void 0,void 0,!0)}focusFirst(){return this.focusedItem=this.length()-1,this.focusNext(!0)}focusLast(){return this.focusedItem=0,this.focusPrevious(!0)}focusNext(e){let t;if(void 0===this.focusedItem)this.focusedItem=this.viewItems.length-1;else if(this.viewItems.length<=1)return!1;let n=this.focusedItem;do{if(!e&&this.options.preventLoopNavigation&&this.focusedItem+1>=this.viewItems.length)return this.focusedItem=n,!1;this.focusedItem=(this.focusedItem+1)%this.viewItems.length,t=this.viewItems[this.focusedItem]}while(this.focusedItem!==n&&(this.options.focusOnlyEnabledItems&&!t.isEnabled()||t.action.id===r.wv.ID))return this.updateFocus(),!0}focusPrevious(e){let t;if(void 0===this.focusedItem)this.focusedItem=0;else if(this.viewItems.length<=1)return!1;let n=this.focusedItem;do{if(this.focusedItem=this.focusedItem-1,this.focusedItem<0){if(!e&&this.options.preventLoopNavigation)return this.focusedItem=n,!1;this.focusedItem=this.viewItems.length-1}t=this.viewItems[this.focusedItem]}while(this.focusedItem!==n&&(this.options.focusOnlyEnabledItems&&!t.isEnabled()||t.action.id===r.wv.ID))return this.updateFocus(!0),!0}updateFocus(e,t,n=!1){var o,i;void 0===this.focusedItem&&this.actionsList.focus({preventScroll:t}),void 0!==this.previouslyFocusedItem&&this.previouslyFocusedItem!==this.focusedItem&&(null==(o=this.viewItems[this.previouslyFocusedItem])||o.blur());let s=void 0!==this.focusedItem?this.viewItems[this.focusedItem]:void 0;if(s){let o=!0;h.Tn(s.focus)||(o=!1),this.options.focusOnlyEnabledItems&&h.Tn(s.isEnabled)&&!s.isEnabled()&&(o=!1),s.action.id===r.wv.ID&&(o=!1),o?(n||this.previouslyFocusedItem!==this.focusedItem)&&(s.focus(e),this.previouslyFocusedItem=this.focusedItem):(this.actionsList.focus({preventScroll:t}),this.previouslyFocusedItem=void 0),o&&(null==(i=s.showHover)||i.call(s))}}doTrigger(e){if(void 0===this.focusedItem)return;let t=this.viewItems[this.focusedItem];if(t instanceof s.EH){let n=null===t._context||void 0===t._context?e:t._context;this.run(t._action,n)}}async run(e,t){await this._actionRunner.run(e,t)}dispose(){this._context=void 0,this.viewItems=(0,c.AS)(this.viewItems),this.getContainer().remove(),super.dispose()}}n.d(t,{E:()=>d})},556066(e,t,n){let o,i,s,a,r;n.d(t,{xE:()=>y,vr:()=>B,h5:()=>k});var l=n(614333),c=n(785072),h=n.n(c),d=n(697825),u=n.n(d),A=n(777659),p=n.n(A),m=n(655056),g=n.n(m),C=n(510540),b=n.n(C),v=n(341113),f=n.n(v),x=n(435038),w={};function B(e){(o=document.createElement("div")).className="monaco-aria-container";let t=()=>{let e=document.createElement("div");return e.className="monaco-alert",e.setAttribute("role","alert"),e.setAttribute("aria-atomic","true"),o.appendChild(e),e};i=t(),s=t();let n=()=>{let e=document.createElement("div");return e.className="monaco-status",e.setAttribute("aria-live","polite"),e.setAttribute("aria-atomic","true"),o.appendChild(e),e};a=n(),r=n(),e.appendChild(o)}function y(e){o&&(i.textContent!==e?(l.w_(s),E(i,e)):(l.w_(i),E(s,e)))}function k(e){o&&(a.textContent!==e?(l.w_(r),E(a,e)):(l.w_(a),E(r,e)))}function E(e,t){l.w_(e),t.length>2e4&&(t=t.substr(0,2e4)),e.textContent=t,e.style.visibility="hidden",e.style.visibility="visible"}w.styleTagTransform=f(),w.setAttributes=g(),w.insert=p().bind(null,"head"),w.domAPI=u(),w.insertStyleElement=b(),h()(x.A,w),x.A&&x.A.locals&&x.A.locals},710387(e,t,n){n.d(t,{$:()=>L});var o=n(614333),i=n(592542),s=n(287594),a=n(827067),r=n(830474),l=n(165568),c=n(991818),h=n(694901),d=n(2106),u=n(390028),A=n(310998),p=n(858881),m=n(785072),g=n.n(m),C=n(697825),b=n.n(C),v=n(777659),f=n.n(v),x=n(655056),w=n.n(x),B=n(510540),y=n.n(B),k=n(341113),E=n.n(k),_=n(18880),D={};D.styleTagTransform=E(),D.setAttributes=w(),D.insert=f().bind(null,"head"),D.domAPI=b(),D.insertStyleElement=y(),g()(_.A,D),_.A&&_.A.locals&&_.A.locals;var I=n(720396);h.Q1.white.toString(),h.Q1.white.toString();class L extends A.jG{get onDidClick(){return this._onDidClick.event}constructor(e,t){super(),this._label="",this._onDidClick=this._register(new d.vl),this._onDidEscape=this._register(new d.vl),this.options=t,this._element=document.createElement("a"),this._element.classList.add("monaco-button"),this._element.tabIndex=0,this._element.setAttribute("role","button"),this._element.classList.toggle("secondary",!!t.secondary);const n=t.secondary?t.buttonSecondaryBackground:t.buttonBackground,i=t.secondary?t.buttonSecondaryForeground:t.buttonForeground;this._element.style.color=i||"",this._element.style.backgroundColor=n||"",t.supportShortLabel&&(this._labelShortElement=document.createElement("div"),this._labelShortElement.classList.add("monaco-button-label-short"),this._element.appendChild(this._labelShortElement),this._labelElement=document.createElement("div"),this._labelElement.classList.add("monaco-button-label"),this._element.appendChild(this._labelElement),this._element.classList.add("monaco-text-button-with-short-label")),"string"==typeof t.title&&this.setTitle(t.title),"string"==typeof t.ariaLabel&&this._element.setAttribute("aria-label",t.ariaLabel),e.appendChild(this._element),this._register(r.q.addTarget(this._element)),[o.Bx.CLICK,r.B.Tap].forEach(e=>{this._register((0,o.ko)(this._element,e,e=>{this.enabled?this._onDidClick.fire(e):o.fs.stop(e)}))}),this._register((0,o.ko)(this._element,o.Bx.KEY_DOWN,e=>{let t=new s.Z(e),n=!1;this.enabled&&(t.equals(3)||t.equals(10))?(this._onDidClick.fire(e),n=!0):t.equals(9)&&(this._onDidEscape.fire(e),this._element.blur(),n=!0),n&&o.fs.stop(t,!0)})),this._register((0,o.ko)(this._element,o.Bx.MOUSE_OVER,e=>{this._element.classList.contains("disabled")||this.updateBackground(!0)})),this._register((0,o.ko)(this._element,o.Bx.MOUSE_OUT,e=>{this.updateBackground(!1)})),this.focusTracker=this._register((0,o.w5)(this._element)),this._register(this.focusTracker.onDidFocus(()=>{this.enabled&&this.updateBackground(!0)})),this._register(this.focusTracker.onDidBlur(()=>{this.enabled&&this.updateBackground(!1)}))}dispose(){super.dispose(),this._element.remove()}getContentElements(e){let t=[];for(let n of(0,c.n)(e))if("string"==typeof n){if(""===(n=n.trim()))continue;let e=document.createElement("span");e.textContent=n,t.push(e)}else t.push(n);return t}updateBackground(e){let t;(t=this.options.secondary?e?this.options.buttonSecondaryHoverBackground:this.options.buttonSecondaryBackground:e?this.options.buttonHoverBackground:this.options.buttonBackground)&&(this._element.style.backgroundColor=t)}get element(){return this._element}set label(e){var t;if(this._label===e||(0,u.VS)(this._label)&&(0,u.VS)(e)&&(0,u.nK)(this._label,e))return;this._element.classList.add("monaco-text-button");let n=this.options.supportShortLabel?this._labelElement:this._element;if((0,u.VS)(e)){let s=(0,a.Gc)(e,{inline:!0});s.dispose();let r=null==(t=s.element.querySelector("p"))?void 0:t.innerHTML;r?n.innerHTML=(0,i.aj)(r,{ADD_TAGS:["b","i","u","code","span"],ALLOWED_ATTR:["class"],RETURN_TRUSTED_TYPE:!0}):(0,o.Ln)(n)}else this.options.supportIcons?(0,o.Ln)(n,...this.getContentElements(e)):n.textContent=e;let s="";"string"==typeof this.options.title?s=this.options.title:this.options.title&&(s=(0,a.R9)(e)),this.setTitle(s),"string"==typeof this.options.ariaLabel?this._element.setAttribute("aria-label",this.options.ariaLabel):this.options.ariaLabel&&this._element.setAttribute("aria-label",s),this._label=e}get label(){return this._label}set icon(e){this._element.classList.add(...p.L.asClassNameArray(e))}set enabled(e){e?(this._element.classList.remove("disabled"),this._element.setAttribute("aria-disabled",String(!1)),this._element.tabIndex=0):(this._element.classList.add("disabled"),this._element.setAttribute("aria-disabled",String(!0)))}get enabled(){return!this._element.classList.contains("disabled")}setTitle(e){var t;this._hover||""===e?this._hover&&this._hover.update(e):this._hover=this._register((0,I.i)().setupUpdatableHover(null!=(t=this.options.hoverDelegate)?t:(0,l.nZ)("mouse"),this._element,e))}}},153806(e,t,n){var o=n(785072),i=n.n(o),s=n(697825),a=n.n(s),r=n(777659),l=n.n(r),c=n(655056),h=n.n(c),d=n(510540),u=n.n(d),A=n(341113),p=n.n(A),m=n(612171),g={};g.styleTagTransform=p(),g.setAttributes=h(),g.insert=l().bind(null,"head"),g.domAPI=a(),g.insertStyleElement=u(),i()(m.A,g),m.A&&m.A.locals&&m.A.locals;var C=n(300714),b={};b.styleTagTransform=p(),b.setAttributes=h(),b.insert=l().bind(null,"head"),b.domAPI=a(),b.insertStyleElement=u(),i()(C.A,b),C.A&&C.A.locals&&C.A.locals},528239(e,t,n){n.d(t,{vx:()=>k,Zp:()=>y});var o,i,s=n(851577),a=n(614333),r=n(310998),l=n(263339),c=n(382199),h=n(785072),d=n.n(h),u=n(697825),A=n.n(u),p=n(777659),m=n.n(p),g=n(655056),C=n.n(g),b=n(510540),v=n.n(b),f=n(341113),x=n.n(f),w=n(908970),B={};function y(e,t,n){let o=n.mode===i.ALIGN?n.offset:n.offset+n.size,s=n.mode===i.ALIGN?n.offset+n.size:n.offset;return 0===n.position?t<=e-o?o:t<=s?s-t:Math.max(e-t,0):t<=s?s-t:t<=e-o?o:0}B.styleTagTransform=x(),B.setAttributes=C(),B.insert=m().bind(null,"head"),B.domAPI=A(),B.insertStyleElement=v(),d()(w.A,B),w.A&&w.A.locals&&w.A.locals,(o=i||(i={}))[o.AVOID=0]="AVOID",o[o.ALIGN=1]="ALIGN";class k extends r.jG{constructor(e,t){super(),this.container=null,this.useFixedPosition=!1,this.useShadowDOM=!1,this.delegate=null,this.toDisposeOnClean=r.jG.None,this.toDisposeOnSetContainer=r.jG.None,this.shadowRoot=null,this.shadowRootHostElement=null,this.view=a.$(".context-view"),a.jD(this.view),this.setContainer(e,t),this._register((0,r.s)(()=>this.setContainer(null,1)))}setContainer(e,t){var n;this.useFixedPosition=1!==t;let o=this.useShadowDOM;if(this.useShadowDOM=3===t,(e!==this.container||o!==this.useShadowDOM)&&(this.container&&(this.toDisposeOnSetContainer.dispose(),this.shadowRoot?(this.shadowRoot.removeChild(this.view),this.shadowRoot=null,null==(n=this.shadowRootHostElement)||n.remove(),this.shadowRootHostElement=null):this.container.removeChild(this.view),this.container=null),e)){if(this.container=e,this.useShadowDOM){this.shadowRootHostElement=a.$(".shadow-root-host"),this.container.appendChild(this.shadowRootHostElement),this.shadowRoot=this.shadowRootHostElement.attachShadow({mode:"open"});let e=document.createElement("style");e.textContent=E,this.shadowRoot.appendChild(e),this.shadowRoot.appendChild(this.view),this.shadowRoot.appendChild(a.$("slot"))}else this.container.appendChild(this.view);let t=new r.Cm;k.BUBBLE_UP_EVENTS.forEach(e=>{t.add(a.b2(this.container,e,e=>{this.onDOMEvent(e,!1)}))}),k.BUBBLE_DOWN_EVENTS.forEach(e=>{t.add(a.b2(this.container,e,e=>{this.onDOMEvent(e,!0)},!0))}),this.toDisposeOnSetContainer=t}}show(e){var t,n,o;this.isVisible()&&this.hide(),a.w_(this.view),this.view.className="context-view monaco-component",this.view.style.top="0px",this.view.style.left="0px",this.view.style.zIndex=`${2575+(null!=(t=e.layer)?t:0)}`,this.view.style.position=this.useFixedPosition?"fixed":"absolute",a.WU(this.view),this.toDisposeOnClean=e.render(this.view)||r.jG.None,this.delegate=e,this.doLayout(),null==(o=(n=this.delegate).focus)||o.call(n)}getViewElement(){return this.view}layout(){var e,t;if(this.isVisible()){if(!1===this.delegate.canRelayout&&!(l.un&&s.e.pointerEvents))return void this.hide();null==(t=null==(e=this.delegate)?void 0:e.layout)||t.call(e),this.doLayout()}}doLayout(){let e,t,n;if(!this.isVisible())return;let o=this.delegate.getAnchor();if(o instanceof HTMLElement){let t=a.BK(o),n=a.mU(o);e={top:t.top*n,left:t.left*n,width:t.width*n,height:t.height*n}}else e=o&&"number"==typeof o.x&&"number"==typeof o.y?{top:o.y,left:o.x,width:o.width||1,height:o.height||2}:{top:o.posy,left:o.posx,width:2,height:2};let s=a.Tr(this.view),r=a.OK(this.view),l=this.delegate.anchorPosition||0,h=this.delegate.anchorAlignment||0,d=this.delegate.anchorAxisAlignment||0,u=a.fz();if(0===d){let o={offset:e.top-u.pageYOffset,size:e.height,position:+(0!==l)},a={offset:e.left,size:e.width,position:+(0!==h),mode:i.ALIGN};t=y(u.innerHeight,r,o)+u.pageYOffset,c.Q.intersects({start:t,end:t+r},{start:o.offset,end:o.offset+o.size})&&(a.mode=i.AVOID),n=y(u.innerWidth,s,a)}else{let o={offset:e.left,size:e.width,position:+(0!==h)},a={offset:e.top,size:e.height,position:+(0!==l),mode:i.ALIGN};n=y(u.innerWidth,s,o),c.Q.intersects({start:n,end:n+s},{start:o.offset,end:o.offset+o.size})&&(a.mode=i.AVOID),t=y(u.innerHeight,r,a)+u.pageYOffset}this.view.classList.remove("top","bottom","left","right"),this.view.classList.add(0===l?"bottom":"top"),this.view.classList.add(0===h?"left":"right"),this.view.classList.toggle("fixed",this.useFixedPosition);let A=a.BK(this.container);this.view.style.top=`${t-(this.useFixedPosition?a.BK(this.view).top:A.top)}px`,this.view.style.left=`${n-(this.useFixedPosition?a.BK(this.view).left:A.left)}px`,this.view.style.width="initial"}hide(e){let t=this.delegate;this.delegate=null,(null==t?void 0:t.onHide)&&t.onHide(e),this.toDisposeOnClean.dispose(),a.jD(this.view)}isVisible(){return!!this.delegate}onDOMEvent(e,t){this.delegate&&(this.delegate.onDOMEvent?this.delegate.onDOMEvent(e,a.zk(e).document.activeElement):t&&!a.QX(e.target,this.container)&&this.hide())}dispose(){this.hide(),super.dispose()}}k.BUBBLE_UP_EVENTS=["click","keydown","focus","blur"],k.BUBBLE_DOWN_EVENTS=["click"];let E=`
	:host {
		all: initial; /* 1st rule so subsequent properties are reset. */
	}

	.codicon[class*='codicon-'] {
		font: normal normal normal 16px/1 codicon;
		display: inline-block;
		text-decoration: none;
		text-rendering: auto;
		text-align: center;
		-webkit-font-smoothing: antialiased;
		-moz-osx-font-smoothing: grayscale;
		user-select: none;
		-webkit-user-select: none;
		-ms-user-select: none;
	}

	:host {
		font-family: -apple-system, BlinkMacSystemFont, "Segoe WPC", "Segoe UI", "HelveticaNeue-Light", system-ui, "Ubuntu", "Droid Sans", sans-serif;
	}

	:host-context(.mac) { font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
	:host-context(.mac:lang(zh-Hans)) { font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", sans-serif; }
	:host-context(.mac:lang(zh-Hant)) { font-family: -apple-system, BlinkMacSystemFont, "PingFang TC", sans-serif; }
	:host-context(.mac:lang(ja)) { font-family: -apple-system, BlinkMacSystemFont, "Hiragino Kaku Gothic Pro", sans-serif; }
	:host-context(.mac:lang(ko)) { font-family: -apple-system, BlinkMacSystemFont, "Nanum Gothic", "Apple SD Gothic Neo", "AppleGothic", sans-serif; }

	:host-context(.windows) { font-family: "Segoe WPC", "Segoe UI", sans-serif; }
	:host-context(.windows:lang(zh-Hans)) { font-family: "Segoe WPC", "Segoe UI", "Microsoft YaHei", sans-serif; }
	:host-context(.windows:lang(zh-Hant)) { font-family: "Segoe WPC", "Segoe UI", "Microsoft Jhenghei", sans-serif; }
	:host-context(.windows:lang(ja)) { font-family: "Segoe WPC", "Segoe UI", "Yu Gothic UI", "Meiryo UI", sans-serif; }
	:host-context(.windows:lang(ko)) { font-family: "Segoe WPC", "Segoe UI", "Malgun Gothic", "Dotom", sans-serif; }

	:host-context(.linux) { font-family: system-ui, "Ubuntu", "Droid Sans", sans-serif; }
	:host-context(.linux:lang(zh-Hans)) { font-family: system-ui, "Ubuntu", "Droid Sans", "Source Han Sans SC", "Source Han Sans CN", "Source Han Sans", sans-serif; }
	:host-context(.linux:lang(zh-Hant)) { font-family: system-ui, "Ubuntu", "Droid Sans", "Source Han Sans TC", "Source Han Sans TW", "Source Han Sans", sans-serif; }
	:host-context(.linux:lang(ja)) { font-family: system-ui, "Ubuntu", "Droid Sans", "Source Han Sans J", "Source Han Sans JP", "Source Han Sans", sans-serif; }
	:host-context(.linux:lang(ko)) { font-family: system-ui, "Ubuntu", "Droid Sans", "Source Han Sans K", "Source Han Sans JR", "Source Han Sans", "UnDotum", "FBaekmuk Gulim", sans-serif; }
`},114507(e,t,n){n.d(t,{x:()=>v});var o=n(614333),i=n(916844),s=n(785072),a=n.n(s),r=n(697825),l=n.n(r),c=n(777659),h=n.n(c),d=n(655056),u=n.n(d),A=n(510540),p=n.n(A),m=n(341113),g=n.n(m),C=n(81684),b={};b.styleTagTransform=g(),b.setAttributes=u(),b.insert=h().bind(null,"head"),b.domAPI=l(),b.insertStyleElement=p(),a()(C.A,b),C.A&&C.A.locals&&C.A.locals;class v{constructor(e,t,n){this.options=t,this.styles=n,this.count=0,this.element=(0,o.BC)(e,(0,o.$)(".monaco-count-badge")),this.countFormat=this.options.countFormat||"{0}",this.titleFormat=this.options.titleFormat||"",this.setCount(this.options.count||0)}setCount(e){this.count=e,this.render()}setTitleFormat(e){this.titleFormat=e,this.render()}render(){var e,t;this.element.textContent=(0,i.GP)(this.countFormat,this.count),this.element.title=(0,i.GP)(this.titleFormat,this.count),this.element.style.backgroundColor=null!=(e=this.styles.badgeBackground)?e:"",this.element.style.color=null!=(t=this.styles.badgeForeground)?t:"",this.styles.badgeBorder&&(this.element.style.border=`1px solid ${this.styles.badgeBorder}`)}}},517589(e,t,n){n.d(t,{d:()=>_});var o=n(614333),i=n(223473),s=n(287594),a=n(830474),r=n(427969),l=n(2106),c=n(785072),h=n.n(c),d=n(697825),u=n.n(d),A=n(777659),p=n.n(A),m=n(655056),g=n.n(m),C=n(510540),b=n.n(C),v=n(341113),f=n.n(v),x=n(979862),w={};w.styleTagTransform=f(),w.setAttributes=g(),w.insert=p().bind(null,"head"),w.domAPI=u(),w.insertStyleElement=b(),h()(x.A,w),x.A&&x.A.locals&&x.A.locals;class B extends r.LN{constructor(e,t){super(),this._onDidChangeVisibility=this._register(new l.vl),this.onDidChangeVisibility=this._onDidChangeVisibility.event,this._element=(0,o.BC)(e,(0,o.$)(".monaco-dropdown")),this._label=(0,o.BC)(this._element,(0,o.$)(".dropdown-label"));let n=t.labelRenderer;for(const e of(n||(n=e=>(e.textContent=t.label||"",null)),[o.Bx.CLICK,o.Bx.MOUSE_DOWN,a.B.Tap]))this._register((0,o.ko)(this.element,e,e=>o.fs.stop(e,!0)));for(const e of[o.Bx.MOUSE_DOWN,a.B.Tap])this._register((0,o.ko)(this._label,e,e=>{(0,o.Er)(e)&&(e.detail>1||0!==e.button)||(this.visible?this.hide():this.show())}));this._register((0,o.ko)(this._label,o.Bx.KEY_UP,e=>{let t=new s.Z(e);(t.equals(3)||t.equals(10))&&(o.fs.stop(e,!0),this.visible?this.hide():this.show())}));const i=n(this._label);i&&this._register(i),this._register(a.q.addTarget(this._label))}get element(){return this._element}show(){this.visible||(this.visible=!0,this._onDidChangeVisibility.fire(!0))}hide(){this.visible&&(this.visible=!1,this._onDidChangeVisibility.fire(!1))}dispose(){super.dispose(),this.hide(),this.boxContainer&&(this.boxContainer.remove(),this.boxContainer=void 0),this.contents&&(this.contents.remove(),this.contents=void 0),this._label&&(this._label.remove(),this._label=void 0)}}class y extends B{constructor(e,t){super(e,t),this._options=t,this._actions=[],this.actions=t.actions||[]}set menuOptions(e){this._menuOptions=e}get menuOptions(){return this._menuOptions}get actions(){return this._options.actionProvider?this._options.actionProvider.getActions():this._actions}set actions(e){this._actions=e}show(){super.show(),this.element.classList.add("active"),this._options.contextMenuProvider.showContextMenu({getAnchor:()=>this.element,getActions:()=>this.actions,getActionsContext:()=>this.menuOptions?this.menuOptions.context:null,getActionViewItem:(e,t)=>this.menuOptions&&this.menuOptions.actionViewItemProvider?this.menuOptions.actionViewItemProvider(e,t):void 0,getKeyBinding:e=>this.menuOptions&&this.menuOptions.getKeyBinding?this.menuOptions.getKeyBinding(e):void 0,getMenuClassName:()=>this._options.menuClassName||"",onHide:()=>this.onHide(),actionRunner:this.menuOptions?this.menuOptions.actionRunner:void 0,anchorAlignment:this.menuOptions?this.menuOptions.anchorAlignment:0,domForShadowRoot:this._options.menuAsChild?this.element:void 0,skipTelemetry:this._options.skipTelemetry})}hide(){super.hide()}onHide(){this.hide(),this.element.classList.remove("active")}}var k=n(165568),E=n(720396);class _ extends i.EH{constructor(e,t,n,o=Object.create(null)){super(null,e,o),this.actionItem=null,this._onDidChangeVisibility=this._register(new l.vl),this.onDidChangeVisibility=this._onDidChangeVisibility.event,this.menuActionsOrProvider=t,this.contextMenuProvider=n,this.options=o,this.options.actionRunner&&(this.actionRunner=this.options.actionRunner)}render(e){this.actionItem=e;let t=e=>{var t;this.element=(0,o.BC)(e,(0,o.$)("a.action-label"));let n=[];return"string"==typeof this.options.classNames?n=this.options.classNames.split(/\s+/g).filter(e=>!!e):this.options.classNames&&(n=this.options.classNames),n.find(e=>"icon"===e)||n.push("codicon"),this.element.classList.add(...n),this.element.setAttribute("role","button"),this.element.setAttribute("aria-haspopup","true"),this.element.setAttribute("aria-expanded","false"),this._action.label&&this._register((0,E.i)().setupUpdatableHover(null!=(t=this.options.hoverDelegate)?t:(0,k.nZ)("mouse"),this.element,this._action.label)),this.element.ariaLabel=this._action.label||"",null},n=Array.isArray(this.menuActionsOrProvider),i={contextMenuProvider:this.contextMenuProvider,labelRenderer:t,menuAsChild:this.options.menuAsChild,actions:n?this.menuActionsOrProvider:void 0,actionProvider:n?void 0:this.menuActionsOrProvider,skipTelemetry:this.options.skipTelemetry};if(this.dropdownMenu=this._register(new y(e,i)),this._register(this.dropdownMenu.onDidChangeVisibility(e=>{var t;null==(t=this.element)||t.setAttribute("aria-expanded",`${e}`),this._onDidChangeVisibility.fire(e)})),this.dropdownMenu.menuOptions={actionViewItemProvider:this.options.actionViewItemProvider,actionRunner:this.actionRunner,getKeyBinding:this.options.keybindingProvider,context:this._context},this.options.anchorAlignmentProvider){let e=this;this.dropdownMenu.menuOptions={...this.dropdownMenu.menuOptions,get anchorAlignment(){return e.options.anchorAlignmentProvider()}}}this.updateTooltip(),this.updateEnabled()}getTooltip(){let e=null;return this.action.tooltip?e=this.action.tooltip:this.action.label&&(e=this.action.label),null!=e?e:void 0}setActionContext(e){super.setActionContext(e),this.dropdownMenu&&(this.dropdownMenu.menuOptions?this.dropdownMenu.menuOptions.context=e:this.dropdownMenu.menuOptions={context:e})}show(){var e;null==(e=this.dropdownMenu)||e.show()}updateEnabled(){var e,t;let n=!this.action.enabled;null==(e=this.actionItem)||e.classList.toggle("disabled",n),null==(t=this.element)||t.classList.toggle("disabled",n)}}},6595(e,t,n){var o=n(614333),i=n(5906),s=n(293114),a=n(345222),r=n(2106);n(137905);var l=n(3765),c=n(310998),h=n(165568);let d=l.kg("defaultLabel","input");class u extends a.x{constructor(e,t,n){super(),this.fixFocusOnOptionClickEnabled=!0,this.imeSessionInProgress=!1,this.additionalTogglesDisposables=this._register(new c.HE),this.additionalToggles=[],this._onDidOptionChange=this._register(new r.vl),this.onDidOptionChange=this._onDidOptionChange.event,this._onKeyDown=this._register(new r.vl),this.onKeyDown=this._onKeyDown.event,this._onMouseDown=this._register(new r.vl),this.onMouseDown=this._onMouseDown.event,this._onInput=this._register(new r.vl),this._onKeyUp=this._register(new r.vl),this._onCaseSensitiveKeyDown=this._register(new r.vl),this.onCaseSensitiveKeyDown=this._onCaseSensitiveKeyDown.event,this._onRegexKeyDown=this._register(new r.vl),this.onRegexKeyDown=this._onRegexKeyDown.event,this._lastHighlightFindOptions=0,this.placeholder=n.placeholder||"",this.validation=n.validation,this.label=n.label||d,this.showCommonFindToggles=!!n.showCommonFindToggles;const a=n.appendCaseSensitiveLabel||"",l=n.appendWholeWordsLabel||"",u=n.appendRegexLabel||"",A=n.history||[],p=!!n.flexibleHeight,m=!!n.flexibleWidth,g=n.flexibleMaxHeight;this.domNode=document.createElement("div"),this.domNode.classList.add("monaco-findInput"),this.inputBox=this._register(new s.mJ(this.domNode,t,{placeholder:this.placeholder||"",ariaLabel:this.label||"",validationOptions:{validation:this.validation},history:A,showHistoryHint:n.showHistoryHint,flexibleHeight:p,flexibleWidth:m,flexibleMaxHeight:g,inputBoxStyles:n.inputBoxStyles}));const C=this._register((0,h.bW)());if(this.showCommonFindToggles){this.regex=this._register(new i.Ix({appendTitle:u,isChecked:!1,hoverDelegate:C,...n.toggleStyles})),this._register(this.regex.onChange(e=>{this._onDidOptionChange.fire(e),!e&&this.fixFocusOnOptionClickEnabled&&this.inputBox.focus(),this.validate()})),this._register(this.regex.onKeyDown(e=>{this._onRegexKeyDown.fire(e)})),this.wholeWords=this._register(new i.nV({appendTitle:l,isChecked:!1,hoverDelegate:C,...n.toggleStyles})),this._register(this.wholeWords.onChange(e=>{this._onDidOptionChange.fire(e),!e&&this.fixFocusOnOptionClickEnabled&&this.inputBox.focus(),this.validate()})),this.caseSensitive=this._register(new i.bc({appendTitle:a,isChecked:!1,hoverDelegate:C,...n.toggleStyles})),this._register(this.caseSensitive.onChange(e=>{this._onDidOptionChange.fire(e),!e&&this.fixFocusOnOptionClickEnabled&&this.inputBox.focus(),this.validate()})),this._register(this.caseSensitive.onKeyDown(e=>{this._onCaseSensitiveKeyDown.fire(e)}));const e=[this.caseSensitive.domNode,this.wholeWords.domNode,this.regex.domNode];this.onkeydown(this.domNode,t=>{if(t.equals(15)||t.equals(17)||t.equals(9)){let n=e.indexOf(this.domNode.ownerDocument.activeElement);if(n>=0){let i=-1;t.equals(17)?i=(n+1)%e.length:t.equals(15)&&(i=0===n?e.length-1:n-1),t.equals(9)?(e[n].blur(),this.inputBox.focus()):i>=0&&e[i].focus(),o.fs.stop(t,!0)}}})}this.controls=document.createElement("div"),this.controls.className="controls",this.controls.style.display=this.showCommonFindToggles?"":"none",this.caseSensitive&&this.controls.append(this.caseSensitive.domNode),this.wholeWords&&this.controls.appendChild(this.wholeWords.domNode),this.regex&&this.controls.appendChild(this.regex.domNode),this.setAdditionalToggles(null==n?void 0:n.additionalToggles),this.controls&&this.domNode.appendChild(this.controls),null==e||e.appendChild(this.domNode),this._register(o.ko(this.inputBox.inputElement,"compositionstart",e=>{this.imeSessionInProgress=!0})),this._register(o.ko(this.inputBox.inputElement,"compositionend",e=>{this.imeSessionInProgress=!1,this._onInput.fire()})),this.onkeydown(this.inputBox.inputElement,e=>this._onKeyDown.fire(e)),this.onkeyup(this.inputBox.inputElement,e=>this._onKeyUp.fire(e)),this.oninput(this.inputBox.inputElement,e=>this._onInput.fire()),this.onmousedown(this.inputBox.inputElement,e=>this._onMouseDown.fire(e))}get onDidChange(){return this.inputBox.onDidChange}layout(e){this.inputBox.layout(),this.updateInputBoxPadding(e.collapsedFindWidget)}enable(){var e,t,n;for(let o of(this.domNode.classList.remove("disabled"),this.inputBox.enable(),null==(e=this.regex)||e.enable(),null==(t=this.wholeWords)||t.enable(),null==(n=this.caseSensitive)||n.enable(),this.additionalToggles))o.enable()}disable(){var e,t,n;for(let o of(this.domNode.classList.add("disabled"),this.inputBox.disable(),null==(e=this.regex)||e.disable(),null==(t=this.wholeWords)||t.disable(),null==(n=this.caseSensitive)||n.disable(),this.additionalToggles))o.disable()}setFocusInputOnOptionClick(e){this.fixFocusOnOptionClickEnabled=e}setEnabled(e){e?this.enable():this.disable()}setAdditionalToggles(e){for(let e of this.additionalToggles)e.domNode.remove();for(let t of(this.additionalToggles=[],this.additionalTogglesDisposables.value=new c.Cm,null!=e?e:[]))this.additionalTogglesDisposables.value.add(t),this.controls.appendChild(t.domNode),this.additionalTogglesDisposables.value.add(t.onChange(e=>{this._onDidOptionChange.fire(e),!e&&this.fixFocusOnOptionClickEnabled&&this.inputBox.focus()})),this.additionalToggles.push(t);this.additionalToggles.length>0&&(this.controls.style.display=""),this.updateInputBoxPadding()}updateInputBoxPadding(e=!1){var t,n,o,i,s,a;e?this.inputBox.paddingRight=0:this.inputBox.paddingRight=(null!=(n=null==(t=this.caseSensitive)?void 0:t.width())?n:0)+(null!=(i=null==(o=this.wholeWords)?void 0:o.width())?i:0)+(null!=(a=null==(s=this.regex)?void 0:s.width())?a:0)+this.additionalToggles.reduce((e,t)=>e+t.width(),0)}getValue(){return this.inputBox.value}setValue(e){this.inputBox.value!==e&&(this.inputBox.value=e)}select(){this.inputBox.select()}focus(){this.inputBox.focus()}getCaseSensitive(){var e,t;return null!=(t=null==(e=this.caseSensitive)?void 0:e.checked)&&t}setCaseSensitive(e){this.caseSensitive&&(this.caseSensitive.checked=e)}getWholeWords(){var e,t;return null!=(t=null==(e=this.wholeWords)?void 0:e.checked)&&t}setWholeWords(e){this.wholeWords&&(this.wholeWords.checked=e)}getRegex(){var e,t;return null!=(t=null==(e=this.regex)?void 0:e.checked)&&t}setRegex(e){this.regex&&(this.regex.checked=e,this.validate())}focusOnCaseSensitive(){var e;null==(e=this.caseSensitive)||e.focus()}highlightFindOptions(){this.domNode.classList.remove("highlight-"+this._lastHighlightFindOptions),this._lastHighlightFindOptions=1-this._lastHighlightFindOptions,this.domNode.classList.add("highlight-"+this._lastHighlightFindOptions)}validate(){this.inputBox.validate()}showMessage(e){this.inputBox.showMessage(e)}clearMessage(){this.inputBox.hideMessage()}}n.d(t,{c:()=>u})},5906(e,t,n){var o=n(165568),i=n(645413),s=n(126048),a=n(3765);let r=a.kg("caseDescription","Match Case"),l=a.kg("wordsDescription","Match Whole Word"),c=a.kg("regexDescription","Use Regular Expression");class h extends i.l{constructor(e){var t;super({icon:s.W.caseSensitive,title:r+e.appendTitle,isChecked:e.isChecked,hoverDelegate:null!=(t=e.hoverDelegate)?t:(0,o.nZ)("element"),inputActiveOptionBorder:e.inputActiveOptionBorder,inputActiveOptionForeground:e.inputActiveOptionForeground,inputActiveOptionBackground:e.inputActiveOptionBackground})}}class d extends i.l{constructor(e){var t;super({icon:s.W.wholeWord,title:l+e.appendTitle,isChecked:e.isChecked,hoverDelegate:null!=(t=e.hoverDelegate)?t:(0,o.nZ)("element"),inputActiveOptionBorder:e.inputActiveOptionBorder,inputActiveOptionForeground:e.inputActiveOptionForeground,inputActiveOptionBackground:e.inputActiveOptionBackground})}}class u extends i.l{constructor(e){var t;super({icon:s.W.regex,title:c+e.appendTitle,isChecked:e.isChecked,hoverDelegate:null!=(t=e.hoverDelegate)?t:(0,o.nZ)("element"),inputActiveOptionBorder:e.inputActiveOptionBorder,inputActiveOptionForeground:e.inputActiveOptionForeground,inputActiveOptionBackground:e.inputActiveOptionBackground})}}n.d(t,{Ix:()=>u,bc:()=>h,nV:()=>d})},509160(e,t,n){var o=n(614333),i=n(645413),s=n(293114),a=n(345222),r=n(126048),l=n(2106);n(137905);var c=n(3765),h=n(165568);let d=c.kg("defaultLabel","input"),u=c.kg("label.preserveCaseToggle","Preserve Case");class A extends i.l{constructor(e){var t;super({icon:r.W.preserveCase,title:u+e.appendTitle,isChecked:e.isChecked,hoverDelegate:null!=(t=e.hoverDelegate)?t:(0,h.nZ)("element"),inputActiveOptionBorder:e.inputActiveOptionBorder,inputActiveOptionForeground:e.inputActiveOptionForeground,inputActiveOptionBackground:e.inputActiveOptionBackground})}}class p extends a.x{constructor(e,t,n,i){super(),this._showOptionButtons=n,this.fixFocusOnOptionClickEnabled=!0,this.cachedOptionsWidth=0,this._onDidOptionChange=this._register(new l.vl),this.onDidOptionChange=this._onDidOptionChange.event,this._onKeyDown=this._register(new l.vl),this.onKeyDown=this._onKeyDown.event,this._onMouseDown=this._register(new l.vl),this._onInput=this._register(new l.vl),this._onKeyUp=this._register(new l.vl),this._onPreserveCaseKeyDown=this._register(new l.vl),this.onPreserveCaseKeyDown=this._onPreserveCaseKeyDown.event,this.contextViewProvider=t,this.placeholder=i.placeholder||"",this.validation=i.validation,this.label=i.label||d;const a=i.appendPreserveCaseLabel||"",r=i.history||[],c=!!i.flexibleHeight,h=!!i.flexibleWidth,u=i.flexibleMaxHeight;this.domNode=document.createElement("div"),this.domNode.classList.add("monaco-findInput"),this.inputBox=this._register(new s.mJ(this.domNode,this.contextViewProvider,{ariaLabel:this.label||"",placeholder:this.placeholder||"",validationOptions:{validation:this.validation},history:r,showHistoryHint:i.showHistoryHint,flexibleHeight:c,flexibleWidth:h,flexibleMaxHeight:u,inputBoxStyles:i.inputBoxStyles})),this.preserveCase=this._register(new A({appendTitle:a,isChecked:!1,...i.toggleStyles})),this._register(this.preserveCase.onChange(e=>{this._onDidOptionChange.fire(e),!e&&this.fixFocusOnOptionClickEnabled&&this.inputBox.focus(),this.validate()})),this._register(this.preserveCase.onKeyDown(e=>{this._onPreserveCaseKeyDown.fire(e)})),this._showOptionButtons?this.cachedOptionsWidth=this.preserveCase.width():this.cachedOptionsWidth=0;const p=[this.preserveCase.domNode];this.onkeydown(this.domNode,e=>{if(e.equals(15)||e.equals(17)||e.equals(9)){let t=p.indexOf(this.domNode.ownerDocument.activeElement);if(t>=0){let n=-1;e.equals(17)?n=(t+1)%p.length:e.equals(15)&&(n=0===t?p.length-1:t-1),e.equals(9)?(p[t].blur(),this.inputBox.focus()):n>=0&&p[n].focus(),o.fs.stop(e,!0)}}});const m=document.createElement("div");m.className="controls",m.style.display=this._showOptionButtons?"block":"none",m.appendChild(this.preserveCase.domNode),this.domNode.appendChild(m),null==e||e.appendChild(this.domNode),this.onkeydown(this.inputBox.inputElement,e=>this._onKeyDown.fire(e)),this.onkeyup(this.inputBox.inputElement,e=>this._onKeyUp.fire(e)),this.oninput(this.inputBox.inputElement,e=>this._onInput.fire()),this.onmousedown(this.inputBox.inputElement,e=>this._onMouseDown.fire(e))}enable(){this.domNode.classList.remove("disabled"),this.inputBox.enable(),this.preserveCase.enable()}disable(){this.domNode.classList.add("disabled"),this.inputBox.disable(),this.preserveCase.disable()}setEnabled(e){e?this.enable():this.disable()}select(){this.inputBox.select()}focus(){this.inputBox.focus()}getPreserveCase(){return this.preserveCase.checked}setPreserveCase(e){this.preserveCase.checked=e}focusOnPreserve(){this.preserveCase.focus()}validate(){var e;null==(e=this.inputBox)||e.validate()}set width(e){this.inputBox.paddingRight=this.cachedOptionsWidth,this.domNode.style.width=e+"px"}dispose(){super.dispose()}}n.d(t,{P:()=>p})},708431(e,t,n){var o=n(614333),i=n(720396),s=n(165568),a=n(991818),r=n(310998),l=n(771386);class c extends r.jG{constructor(e,t){var n;super(),this.options=t,this.text="",this.title="",this.highlights=[],this.didEverRender=!1,this.supportIcons=null!=(n=null==t?void 0:t.supportIcons)&&n,this.domNode=o.BC(e,o.$("span.monaco-highlighted-label"))}get element(){return this.domNode}set(e,t=[],n="",o){e||(e=""),o&&(e=c.escapeNewLines(e,t)),this.didEverRender&&this.text===e&&this.title===n&&l.aI(this.highlights,t)||(this.text=e,this.title=n,this.highlights=t,this.render())}render(){var e,t,n,r;let l=[],c=0;for(let e of this.highlights){if(e.end===e.start)continue;if(c<e.start){let t=this.text.substring(c,e.start);this.supportIcons?l.push(...(0,a.n)(t)):l.push(t),c=e.start}let t=this.text.substring(c,e.end),n=o.$("span.highlight",void 0,...this.supportIcons?(0,a.n)(t):[t]);e.extraClasses&&n.classList.add(...e.extraClasses),l.push(n),c=e.end}if(c<this.text.length){let e=this.text.substring(c);this.supportIcons?l.push(...(0,a.n)(e)):l.push(e)}if(o.Ln(this.domNode,...l),null==(t=null==(e=this.options)?void 0:e.hoverDelegate)?void 0:t.showNativeHover)this.domNode.title=this.title;else if(this.customHover||""===this.title)this.customHover&&this.customHover.update(this.title);else{let e=null!=(r=null==(n=this.options)?void 0:n.hoverDelegate)?r:(0,s.nZ)("mouse");this.customHover=this._register((0,i.i)().setupUpdatableHover(e,this.domNode,this.title))}this.didEverRender=!0}static escapeNewLines(e,t){let n=0,o=0;return e.replace(/\r\n|\r|\n/g,(e,i)=>{for(let s of(o="\r\n"===e?-1:0,i+=n,t))!(s.end<=i)&&(s.start>=i&&(s.start+=o),s.end>=i&&(s.end+=o));return n+=o,"\u23CE"})}}n.d(t,{_:()=>c})},720396(e,t,n){let o={showHover:()=>void 0,hideHover:()=>void 0,showAndFocusLastHover:()=>void 0,setupUpdatableHover:()=>null};function i(e){o=e}function s(){return o}n.d(t,{e:()=>i,i:()=>s})},165568(e,t,n){var o=n(163946);let i=()=>({get delay(){return -1},dispose:()=>{},showHover:()=>{}}),s=new o.d(()=>i("mouse",!1)),a=new o.d(()=>i("element",!1));function r(e){i=e}function l(e){return"element"===e?a.value:s.value}function c(){return i("element",!0)}n.d(t,{MW:()=>r,bW:()=>c,nZ:()=>l})},510059(e,t,n){n.d(t,{vV:()=>E,jQ:()=>y,N4:()=>B,M4:()=>_,vr:()=>k});var o=n(614333),i=n(287594),s=n(82208),a=n(310998),r=n(785072),l=n.n(r),c=n(697825),h=n.n(c),d=n(777659),u=n.n(d),A=n(655056),p=n.n(A),m=n(510540),g=n.n(m),C=n(341113),b=n.n(C),v=n(858694),f={};f.styleTagTransform=b(),f.setAttributes=p(),f.insert=u().bind(null,"head"),f.domAPI=h(),f.insertStyleElement=g(),l()(v.A,f),v.A&&v.A.locals&&v.A.locals;var x=n(3765);let w=o.$;class B extends a.jG{constructor(){super(),this.containerDomNode=document.createElement("div"),this.containerDomNode.className="monaco-hover",this.containerDomNode.tabIndex=0,this.containerDomNode.setAttribute("role","tooltip"),this.contentsDomNode=document.createElement("div"),this.contentsDomNode.className="monaco-hover-content",this.scrollbar=this._register(new s.MU(this.contentsDomNode,{consumeMouseWheelIfScrollbarIsNeeded:!0})),this.containerDomNode.appendChild(this.scrollbar.getDomNode())}onContentsChanged(){this.scrollbar.scanDomNode()}}class y extends a.jG{static render(e,t,n){return new y(e,t,n)}constructor(e,t,n){super(),this.actionContainer=o.BC(e,w("div.action-container")),this.actionContainer.setAttribute("tabindex","0"),this.action=o.BC(this.actionContainer,w("a.action")),this.action.setAttribute("role","button"),t.iconClass&&o.BC(this.action,w(`span.icon.${t.iconClass}`)),o.BC(this.action,w("span")).textContent=n?`${t.label} (${n})`:t.label,this._store.add(new E(this.actionContainer,t.run)),this._store.add(new _(this.actionContainer,t.run,[3,10])),this.setEnabled(!0)}setEnabled(e){e?(this.actionContainer.classList.remove("disabled"),this.actionContainer.removeAttribute("aria-disabled")):(this.actionContainer.classList.add("disabled"),this.actionContainer.setAttribute("aria-disabled","true"))}}function k(e,t){return e&&t?(0,x.kg)("acessibleViewHint","Inspect this in the accessible view with {0}.",t):e?(0,x.kg)("acessibleViewHintNoKbOpen","Inspect this in the accessible view via the command Open Accessible View which is currently not triggerable via keybinding."):""}class E extends a.jG{constructor(e,t){super(),this._register(o.ko(e,o.Bx.CLICK,n=>{n.stopPropagation(),n.preventDefault(),t(e)}))}}class _ extends a.jG{constructor(e,t,n){super(),this._register(o.ko(e,o.Bx.KEY_DOWN,o=>{let s=new i.Z(o);n.some(e=>s.equals(e))&&(o.stopPropagation(),o.preventDefault(),t(e))}))}}},13761(e,t,n){n.d(t,{s:()=>_});var o=n(785072),i=n.n(o),s=n(697825),a=n.n(s),r=n(777659),l=n.n(r),c=n(655056),h=n.n(c),d=n(510540),u=n.n(d),A=n(341113),p=n.n(A),m=n(348134),g={};g.styleTagTransform=p(),g.setAttributes=h(),g.insert=l().bind(null,"head"),g.domAPI=a(),g.insertStyleElement=u(),i()(m.A,g),m.A&&m.A.locals&&m.A.locals;var C=n(614333),b=n(708431),v=n(310998),f=n(771386),x=n(382199),w=n(165568),B=n(720396),y=n(779359),k=n(324594);class E{constructor(e){this._element=e}get element(){return this._element}set textContent(e){this.disposed||e===this._textContent||(this._textContent=e,this._element.textContent=e)}set className(e){this.disposed||e===this._className||(this._className=e,this._element.className=e)}set empty(e){this.disposed||e===this._empty||(this._empty=e,this._element.style.marginLeft=e?"0":"")}dispose(){this.disposed=!0}}class _ extends v.jG{constructor(e,t){var n;super(),this.customHovers=new Map,this.creationOptions=t,this.domNode=this._register(new E(C.BC(e,C.$(".monaco-icon-label")))),this.labelContainer=C.BC(this.domNode.element,C.$(".monaco-icon-label-container")),this.nameContainer=C.BC(this.labelContainer,C.$("span.monaco-icon-name-container")),(null==t?void 0:t.supportHighlights)||(null==t?void 0:t.supportIcons)?this.nameNode=this._register(new I(this.nameContainer,!!t.supportIcons)):this.nameNode=new D(this.nameContainer),this.hoverDelegate=null!=(n=null==t?void 0:t.hoverDelegate)?n:(0,w.nZ)("mouse")}get element(){return this.domNode.element}setLabel(e,t,n){var o;let i=["monaco-icon-label"],s=["monaco-icon-label-container"],a="";if(n&&(n.extraClasses&&i.push(...n.extraClasses),n.italic&&i.push("italic"),n.strikethrough&&i.push("strikethrough"),n.disabledCommand&&s.push("disabled"),n.title&&("string"==typeof n.title?a+=n.title:a+=e)),this.domNode.className=i.join(" "),this.domNode.element.setAttribute("aria-label",a),this.labelContainer.className=s.join(" "),this.setupHover((null==n?void 0:n.descriptionTitle)?this.labelContainer:this.element,null==n?void 0:n.title),this.nameNode.setLabel(e,n),t||this.descriptionNode){let e=this.getOrCreateDescriptionNode();e instanceof b._?(e.set(t||"",n?n.descriptionMatches:void 0,void 0,null==n?void 0:n.labelEscapeNewLines),this.setupHover(e.element,null==n?void 0:n.descriptionTitle)):(e.textContent=t&&(null==n?void 0:n.labelEscapeNewLines)?b._.escapeNewLines(t,[]):t||"",this.setupHover(e.element,(null==n?void 0:n.descriptionTitle)||""),e.empty=!t)}((null==n?void 0:n.suffix)||this.suffixNode)&&(this.getOrCreateSuffixNode().textContent=null!=(o=null==n?void 0:n.suffix)?o:"")}setupHover(e,t){let n=this.customHovers.get(e);if(n&&(n.dispose(),this.customHovers.delete(e)),!t)return void e.removeAttribute("title");if(this.hoverDelegate.showNativeHover)(0,y.Kg)(t)?e.title=(0,k.pS)(t):(null==t?void 0:t.markdownNotSupportedFallback)?e.title=t.markdownNotSupportedFallback:e.removeAttribute("title");else{let n=(0,B.i)().setupUpdatableHover(this.hoverDelegate,e,t);n&&this.customHovers.set(e,n)}}dispose(){for(let e of(super.dispose(),this.customHovers.values()))e.dispose();this.customHovers.clear()}getOrCreateSuffixNode(){if(!this.suffixNode){let e=this._register(new E(C.Pl(this.nameContainer,C.$("span.monaco-icon-suffix-container"))));this.suffixNode=this._register(new E(C.BC(e.element,C.$("span.label-suffix"))))}return this.suffixNode}getOrCreateDescriptionNode(){var e;if(!this.descriptionNode){let t=this._register(new E(C.BC(this.labelContainer,C.$("span.monaco-icon-description-container"))));(null==(e=this.creationOptions)?void 0:e.supportDescriptionHighlights)?this.descriptionNode=this._register(new b._(C.BC(t.element,C.$("span.label-description")),{supportIcons:!!this.creationOptions.supportIcons})):this.descriptionNode=this._register(new E(C.BC(t.element,C.$("span.label-description"))))}return this.descriptionNode}}class D{constructor(e){this.container=e,this.label=void 0,this.singleLabel=void 0}setLabel(e,t){if(!(this.label===e&&(0,f.aI)(this.options,t)))if(this.label=e,this.options=t,"string"==typeof e)this.singleLabel||(this.container.innerText="",this.container.classList.remove("multiple"),this.singleLabel=C.BC(this.container,C.$("a.label-name",{id:null==t?void 0:t.domId}))),this.singleLabel.textContent=e;else{this.container.innerText="",this.container.classList.add("multiple"),this.singleLabel=void 0;for(let n=0;n<e.length;n++){let o=e[n],i=(null==t?void 0:t.domId)&&`${null==t?void 0:t.domId}_${n}`;C.BC(this.container,C.$("a.label-name",{id:i,"data-icon-label-count":e.length,"data-icon-label-index":n,role:"treeitem"},o)),n<e.length-1&&C.BC(this.container,C.$("span.label-separator",void 0,(null==t?void 0:t.separator)||"/"))}}}}class I extends v.jG{constructor(e,t){super(),this.container=e,this.supportIcons=t,this.label=void 0,this.singleLabel=void 0}setLabel(e,t){if(!(this.label===e&&(0,f.aI)(this.options,t)))if(this.label=e,this.options=t,"string"==typeof e)this.singleLabel||(this.container.innerText="",this.container.classList.remove("multiple"),this.singleLabel=this._register(new b._(C.BC(this.container,C.$("a.label-name",{id:null==t?void 0:t.domId})),{supportIcons:this.supportIcons}))),this.singleLabel.set(e,null==t?void 0:t.matches,void 0,null==t?void 0:t.labelEscapeNewLines);else{this.container.innerText="",this.container.classList.add("multiple"),this.singleLabel=void 0;let n=(null==t?void 0:t.separator)||"/",o=function(e,t,n){if(!n)return;let o=0;return e.map(e=>{let i={start:o,end:o+e.length},s=n.map(e=>x.Q.intersect(i,e)).filter(e=>!x.Q.isEmpty(e)).map(({start:e,end:t})=>({start:e-o,end:t-o}));return o=i.end+t.length,s})}(e,n,null==t?void 0:t.matches);for(let i=0;i<e.length;i++){let s=e[i],a=o?o[i]:void 0,r=(null==t?void 0:t.domId)&&`${null==t?void 0:t.domId}_${i}`,l=C.$("a.label-name",{id:r,"data-icon-label-count":e.length,"data-icon-label-index":i,role:"treeitem"});this._register(new b._(C.BC(this.container,l),{supportIcons:this.supportIcons})).set(s,a,void 0,null==t?void 0:t.labelEscapeNewLines),i<e.length-1&&C.BC(l,C.$("span.label-separator",void 0,n))}}}}},991818(e,t,n){var o=n(614333),i=n(858881);let s=RegExp(`(\\\\)?\\$\\((${i.L.iconNameExpression}(?:${i.L.iconModifierExpression})?)\\)`,"g");function a(e){let t,n=[],o=0,i=0;for(;null!==(t=s.exec(e));){o<(i=t.index||0)&&n.push(e.substring(o,i)),o=(t.index||0)+t[0].length;let[,s,a]=t;n.push(s?`$(${a})`:r({id:a}))}return o<e.length&&n.push(e.substring(o)),n}function r(e){let t=o.$("span");return t.classList.add(...i.L.asClassNameArray(e)),t}n.d(t,{n:()=>a,s:()=>r})},293114(e,t,n){n.d(t,{mJ:()=>N,x8:()=>T});var o=n(614333),i=n(934061),s=n(488213),a=n(777439),r=n(556066),l=n(720396),c=n(165568),h=n(82208),d=n(345222),u=n(2106),A=n(508310),p=n(771386),m=n(785072),g=n.n(m),C=n(697825),b=n.n(C),v=n(777659),f=n.n(v),x=n(655056),w=n.n(x),B=n(510540),y=n.n(B),k=n(341113),E=n.n(k),_=n(1366),D={};D.styleTagTransform=E(),D.setAttributes=w(),D.insert=f().bind(null,"head"),D.domAPI=b(),D.insertStyleElement=y(),g()(_.A,D),_.A&&_.A.locals&&_.A.locals;var I=n(3765);let L=o.$,T={inputBackground:"#3C3C3C",inputForeground:"#CCCCCC",inputValidationInfoBorder:"#55AAFF",inputValidationInfoBackground:"#063B49",inputValidationWarningBorder:"#B89500",inputValidationWarningBackground:"#352A05",inputValidationErrorBorder:"#BE1100",inputValidationErrorBackground:"#5A1D1D",inputBorder:void 0,inputValidationErrorForeground:void 0,inputValidationInfoForeground:void 0,inputValidationWarningForeground:void 0};class S extends d.x{constructor(e,t,n){var s;super(),this.state="idle",this.maxHeight=1/0,this._onDidChange=this._register(new u.vl),this.onDidChange=this._onDidChange.event,this._onDidHeightChange=this._register(new u.vl),this.onDidHeightChange=this._onDidHeightChange.event,this.contextViewProvider=t,this.options=n,this.message=null,this.placeholder=this.options.placeholder||"",this.tooltip=null!=(s=this.options.tooltip)?s:this.placeholder||"",this.ariaLabel=this.options.ariaLabel||"",this.options.validationOptions&&(this.validation=this.options.validationOptions.validation),this.element=o.BC(e,L(".monaco-inputbox.idle"));const r=this.options.flexibleHeight?"textarea":"input",l=o.BC(this.element,L(".ibwrapper"));if(this.input=o.BC(l,L(r+".input.empty")),this.input.setAttribute("autocorrect","off"),this.input.setAttribute("autocapitalize","off"),this.input.setAttribute("spellcheck","false"),this.onfocus(this.input,()=>this.element.classList.add("synthetic-focus")),this.onblur(this.input,()=>this.element.classList.remove("synthetic-focus")),this.options.flexibleHeight){this.maxHeight="number"==typeof this.options.flexibleMaxHeight?this.options.flexibleMaxHeight:1/0,this.mirror=o.BC(l,L("div.mirror")),this.mirror.innerText="\xa0",this.scrollableElement=new h.Se(this.element,{vertical:1}),this.options.flexibleWidth&&(this.input.setAttribute("wrap","off"),this.mirror.style.whiteSpace="pre",this.mirror.style.wordWrap="initial"),o.BC(e,this.scrollableElement.getDomNode()),this._register(this.scrollableElement),this._register(this.scrollableElement.onScroll(e=>this.input.scrollTop=e.scrollTop));const t=this._register(new i.f(e.ownerDocument,"selectionchange")),n=u.Jh.filter(t.event,()=>{let t=e.ownerDocument.getSelection();return(null==t?void 0:t.anchorNode)===l});this._register(n(this.updateScrollDimensions,this)),this._register(this.onDidHeightChange(this.updateScrollDimensions,this))}else this.input.type=this.options.type||"text",this.input.setAttribute("wrap","off");this.ariaLabel&&this.input.setAttribute("aria-label",this.ariaLabel),this.placeholder&&!this.options.showPlaceholderOnFocus&&this.setPlaceHolder(this.placeholder),this.tooltip&&this.setTooltip(this.tooltip),this.oninput(this.input,()=>this.onValueChange()),this.onblur(this.input,()=>this.onBlur()),this.onfocus(this.input,()=>this.onFocus()),this._register(this.ignoreGesture(this.input)),setTimeout(()=>this.updateMirror(),0),this.options.actions&&(this.actionbar=this._register(new a.E(this.element)),this.actionbar.push(this.options.actions,{icon:!0,label:!1})),this.applyStyles()}onBlur(){this._hideMessage(),this.options.showPlaceholderOnFocus&&this.input.setAttribute("placeholder","")}onFocus(){this._showMessage(),this.options.showPlaceholderOnFocus&&this.input.setAttribute("placeholder",this.placeholder||"")}setPlaceHolder(e){this.placeholder=e,this.input.setAttribute("placeholder",e)}setTooltip(e){this.tooltip=e,this.hover?this.hover.update(e):this.hover=this._register((0,l.i)().setupUpdatableHover((0,c.nZ)("mouse"),this.input,e))}get inputElement(){return this.input}get value(){return this.input.value}set value(e){this.input.value!==e&&(this.input.value=e,this.onValueChange())}get height(){return"number"==typeof this.cachedHeight?this.cachedHeight:o.OK(this.element)}focus(){this.input.focus()}blur(){this.input.blur()}hasFocus(){return o.X7(this.input)}select(e=null){this.input.select(),e&&(this.input.setSelectionRange(e.start,e.end),e.end===this.input.value.length&&(this.input.scrollLeft=this.input.scrollWidth))}isSelectionAtEnd(){return this.input.selectionEnd===this.input.value.length&&this.input.selectionStart===this.input.selectionEnd}getSelection(){var e;let t=this.input.selectionStart;if(null===t)return null;let n=null!=(e=this.input.selectionEnd)?e:t;return{start:t,end:n}}enable(){this.input.removeAttribute("disabled")}disable(){this.blur(),this.input.disabled=!0,this._hideMessage()}set paddingRight(e){this.input.style.width=`calc(100% - ${e}px)`,this.mirror&&(this.mirror.style.paddingRight=e+"px")}updateScrollDimensions(){if("number"!=typeof this.cachedContentHeight||"number"!=typeof this.cachedHeight||!this.scrollableElement)return;let e=this.cachedContentHeight,t=this.cachedHeight,n=this.input.scrollTop;this.scrollableElement.setScrollDimensions({scrollHeight:e,height:t}),this.scrollableElement.setScrollPosition({scrollTop:n})}showMessage(e,t){if("open"===this.state&&(0,p.aI)(this.message,e))return;this.message=e,this.element.classList.remove("idle"),this.element.classList.remove("info"),this.element.classList.remove("warning"),this.element.classList.remove("error"),this.element.classList.add(this.classForType(e.type));let n=this.stylesForType(this.message.type);this.element.style.border=`1px solid ${o.gI(n.border,"transparent")}`,this.message.content&&(this.hasFocus()||t)&&this._showMessage()}hideMessage(){this.message=null,this.element.classList.remove("info"),this.element.classList.remove("warning"),this.element.classList.remove("error"),this.element.classList.add("idle"),this._hideMessage(),this.applyStyles()}validate(){let e=null;return this.validation&&((e=this.validation(this.value))?(this.inputElement.setAttribute("aria-invalid","true"),this.showMessage(e)):this.inputElement.hasAttribute("aria-invalid")&&(this.inputElement.removeAttribute("aria-invalid"),this.hideMessage())),null==e?void 0:e.type}stylesForType(e){let t=this.options.inputBoxStyles;switch(e){case 1:return{border:t.inputValidationInfoBorder,background:t.inputValidationInfoBackground,foreground:t.inputValidationInfoForeground};case 2:return{border:t.inputValidationWarningBorder,background:t.inputValidationWarningBackground,foreground:t.inputValidationWarningForeground};default:return{border:t.inputValidationErrorBorder,background:t.inputValidationErrorBackground,foreground:t.inputValidationErrorForeground}}}classForType(e){switch(e){case 1:return"info";case 2:return"warning";default:return"error"}}_showMessage(){let e,t;if(!this.contextViewProvider||!this.message)return;let n=()=>e.style.width=o.Tr(this.element)+"px";this.contextViewProvider.showContextView({getAnchor:()=>this.element,anchorAlignment:1,render:t=>{var i,a;if(!this.message)return null;e=o.BC(t,L(".monaco-inputbox-container")),n();let r={inline:!0,className:"monaco-inputbox-message"},l=this.message.formatContent?(0,s.yk)(this.message.content,r):(0,s.S5)(this.message.content,r);l.classList.add(this.classForType(this.message.type));let c=this.stylesForType(this.message.type);return l.style.backgroundColor=null!=(i=c.background)?i:"",l.style.color=null!=(a=c.foreground)?a:"",l.style.border=c.border?`1px solid ${c.border}`:"",o.BC(e,l),null},onHide:()=>{this.state="closed"},layout:n}),t=3===this.message.type?I.kg("alertErrorMessage","Error: {0}",this.message.content):2===this.message.type?I.kg("alertWarningMessage","Warning: {0}",this.message.content):I.kg("alertInfoMessage","Info: {0}",this.message.content),r.xE(t),this.state="open"}_hideMessage(){this.contextViewProvider&&("open"===this.state&&this.contextViewProvider.hideContextView(),this.state="idle")}onValueChange(){this._onDidChange.fire(this.value),this.validate(),this.updateMirror(),this.input.classList.toggle("empty",!this.value),"open"===this.state&&this.contextViewProvider&&this.contextViewProvider.layout()}updateMirror(){if(!this.mirror)return;let e=this.value,t=10===e.charCodeAt(e.length-1)?" ":"";(e+t).replace(/\u000c/g,"")?this.mirror.textContent=e+t:this.mirror.innerText="\xa0",this.layout()}applyStyles(){var e,t,n;let i=this.options.inputBoxStyles,s=null!=(e=i.inputBackground)?e:"",a=null!=(t=i.inputForeground)?t:"",r=null!=(n=i.inputBorder)?n:"";this.element.style.backgroundColor=s,this.element.style.color=a,this.input.style.backgroundColor="inherit",this.input.style.color=a,this.element.style.border=`1px solid ${o.gI(r,"transparent")}`}layout(){if(!this.mirror)return;let e=this.cachedContentHeight;this.cachedContentHeight=o.OK(this.mirror),e!==this.cachedContentHeight&&(this.cachedHeight=Math.min(this.cachedContentHeight,this.maxHeight),this.input.style.height=this.cachedHeight+"px",this._onDidHeightChange.fire(this.cachedContentHeight))}insertAtCursor(e){let t=this.inputElement,n=t.selectionStart,o=t.selectionEnd,i=t.value;null!==n&&null!==o&&(this.value=i.substr(0,n)+e+i.substr(o),t.setSelectionRange(n+1,n+1),this.layout())}dispose(){var e;this._hideMessage(),this.message=null,null==(e=this.actionbar)||e.dispose(),super.dispose()}}class N extends S{constructor(e,t,n){const i=I.kg({key:"history.inputbox.hint.suffix.noparens",comment:['Text is the suffix of an input field placeholder coming after the action the input field performs, this will be used when the input field ends in a closing parenthesis ")", for example "Filter (e.g. text, !exclude)". The character inserted into the final string is \u21C5 to represent the up and down arrow keys.']}," or {0} for history","\u21C5"),s=I.kg({key:"history.inputbox.hint.suffix.inparens",comment:['Text is the suffix of an input field placeholder coming after the action the input field performs, this will be used when the input field does NOT end in a closing parenthesis (eg. "Find"). The character inserted into the final string is \u21C5 to represent the up and down arrow keys.']}," ({0} for history)","\u21C5");super(e,t,n),this._onDidFocus=this._register(new u.vl),this.onDidFocus=this._onDidFocus.event,this._onDidBlur=this._register(new u.vl),this.onDidBlur=this._onDidBlur.event,this.history=new A.o(n.history,100);const a=()=>{if(n.showHistoryHint&&n.showHistoryHint()&&!this.placeholder.endsWith(i)&&!this.placeholder.endsWith(s)&&this.history.getHistory().length){let e=this.placeholder.endsWith(")")?i:s,t=this.placeholder+e;n.showPlaceholderOnFocus&&!o.X7(this.input)?this.placeholder=t:this.setPlaceHolder(t)}};this.observer=new MutationObserver((e,t)=>{e.forEach(e=>{e.target.textContent||a()})}),this.observer.observe(this.input,{attributeFilter:["class"]}),this.onfocus(this.input,()=>a()),this.onblur(this.input,()=>{let e=e=>{if(!this.placeholder.endsWith(e))return!1;{let t=this.placeholder.slice(0,this.placeholder.length-e.length);return n.showPlaceholderOnFocus?this.placeholder=t:this.setPlaceHolder(t),!0}};e(s)||e(i)})}dispose(){super.dispose(),this.observer&&(this.observer.disconnect(),this.observer=void 0)}addToHistory(e){this.value&&(e||this.value!==this.getCurrentValue())&&this.history.add(this.value)}isAtLastInHistory(){return this.history.isLast()}isNowhereInHistory(){return this.history.isNowhere()}showNextValue(){this.history.has(this.value)||this.addToHistory();let e=this.getNextValue();e&&(e=e===this.value?this.getNextValue():e),this.value=null!=e?e:"",r.h5(this.value?this.value:I.kg("clearedInput","Cleared Input"))}showPreviousValue(){this.history.has(this.value)||this.addToHistory();let e=this.getPreviousValue();e&&(e=e===this.value?this.getPreviousValue():e),e&&(this.value=e,r.h5(this.value))}setPlaceHolder(e){super.setPlaceHolder(e),this.setTooltip(e)}onBlur(){super.onBlur(),this._onDidBlur.fire()}onFocus(){super.onFocus(),this._onDidFocus.fire()}getCurrentValue(){let e=this.history.current();return e||(e=this.history.last(),this.history.next()),e}getPreviousValue(){return this.history.previous()||this.history.first()}getNextValue(){return this.history.next()}}},896861(e,t,n){var o=n(785072),i=n.n(o),s=n(697825),a=n.n(s),r=n(777659),l=n.n(r),c=n(655056),h=n.n(c),d=n(510540),u=n.n(d),A=n(341113),p=n.n(A),m=n(294566),g={};g.styleTagTransform=p(),g.setAttributes=h(),g.insert=l().bind(null,"head"),g.domAPI=a(),g.insertStyleElement=u(),i()(m.A,g),m.A&&m.A.locals&&m.A.locals},137905(e,t,n){var o=n(785072),i=n.n(o),s=n(697825),a=n.n(s),r=n(777659),l=n.n(r),c=n(655056),h=n.n(c),d=n(510540),u=n.n(d),A=n(341113),p=n.n(A),m=n(408474),g={};g.styleTagTransform=p(),g.setAttributes=h(),g.insert=l().bind(null,"head"),g.domAPI=a(),g.insertStyleElement=u(),i()(m.A,g),m.A&&m.A.locals&&m.A.locals},818880(e,t,n){e.exports=n.p+"codicon-81ea7998906c6b7c.ttf"}}]);
//# sourceMappingURL=21118-45af7f3d0f5ab7c5-4f159888fa236bdc.js.map