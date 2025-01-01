// @ts-check

const {ESLintUtils} = require('@typescript-eslint/utils')
/** @typedef {import('@typescript-eslint/types').TSESTree.JSXAttribute} JSXAttribute */

const propNameRegex = /[Ss]x$/

const components = new Set([
  // 'ActionList.Description',
  // 'ActionList.Divider',
  // 'ActionList.Group',
  // 'ActionList.GroupHeading',
  // 'ActionList.Heading',
  // 'ActionList.Item',
  // 'ActionList.LeadingVisual',
  // 'ActionList.LinkItem',
  // 'ActionList',
  // 'ActionMenu.Button',
  // 'ActionMenu.Overlay',
  // 'Autocomplete.Input',
  // 'Autocomplete.Overlay',
  'Avatar',
  'AvatarStack',
  'BaseStyles',
  // 'Box',
  // 'BranchName',
  // 'Breadcrumbs.Item',
  // 'Breadcrumbs',
  // 'Button',
  // 'ButtonBase',
  'ButtonGroup',
  'Checkbox',
  // 'CircleBadge.Icon',
  // 'CircleBadge',
  // 'CircleOcticon',
  // 'CounterLabel',
  'Details',
  // 'Dialog.Body',
  // 'Dialog.Footer',
  // 'Dialog.Header',
  // 'Dialog.Title',
  // 'Dialog',
  // 'Flash',
  // 'FormControl.Caption',
  // 'FormControl.Label',
  // 'FormControl.Validation',
  // 'FormControl',
  // 'Header.Item',
  'Header',
  // 'Heading',
  // 'IconButton',
  'InlineMessage',
  // 'Label',
  'LabelGroup',
  // 'Link',
  // 'LinkButton',
  // 'NavList.Group',
  // 'NavList.Item',
  // 'NavList.LeadingVisual',
  // 'NavList',
  // 'Octicon',
  // 'Overlay',
  'Pagehead',
  // 'PageHeader.Actions',
  // 'PageHeader.Title',
  // 'PageHeader.TitleArea',
  // 'PageHeader',
  // 'PageLayout.Content',
  // 'PageLayout.Header',
  // 'PageLayout.Pane',
  // 'PageLayout',
  'Pagination',
  // 'Popover.Content',
  // 'Popover',
  // 'ProgressBar.Item',
  // 'ProgressBar',
  'Radio',
  'RadioGroup.Label',
  'RadioGroup',
  // 'RelativeTime',
  // 'SegmentedControl.Button',
  // 'SegmentedControl',
  // 'Select',
  'SelectPanel',
  'SideNav',
  'SkeletonBox',
  // 'Spinner',
  // 'SplitPageLayout.Content',
  // 'SplitPageLayout.Pane',
  // 'SplitPageLayout',
  'SubNav',
  // 'Stack',
  // 'StateLabel',
  // 'Table.Container',
  // 'TabNav.Link',
  // 'TabNav',
  // 'Text',
  // 'Timeline.Badge',
  // 'Timeline.Body',
  // 'Timeline.Item',
  'Timeline',
  // 'ToggleSwitch',
  // 'Token',
  // 'Tooltip',
  'TreeView',
  // 'Truncate',
  // 'UnderlineNav.Item',
  // 'UnderlineNav.Link',
  // 'UnderlineNav',
  // 'UnderlinePanels.Panel',
  // 'UnderlinePanels',
  'VisuallyHidden',
])

module.exports = ESLintUtils.RuleCreator.withoutDocs({
  meta: {
    docs: {
      description: 'This component no longer supports the sx and will soon be removed.',
    },
    messages: {
      noSxComponents:
        'This component has migrated to CSS Modules. Instead of styling with `sx`, add styles to the corresponding `module.css` file and use `className` for selection.',
    },
    type: 'problem',
    schema: [],
  },
  defaultOptions: [],
  create(context) {
    return {
      JSXAttribute(node) {
        if (node.name.type === 'JSXIdentifier' && propNameRegex.test(node.name.name)) {
          const parentNode = node.parent
          const openingElement = parentNode.parent.openingElement

          let componentName

          if (
            openingElement.name.type === 'JSXMemberExpression' &&
            openingElement.name.object.type === 'JSXIdentifier' &&
            openingElement.name.property.type === 'JSXIdentifier'
          ) {
            componentName = `${openingElement.name.object.name}.${openingElement.name.property.name}`
          } else if (openingElement.name.type === 'JSXIdentifier') {
            componentName = openingElement.name.name
          }

          if (componentName && components.has(componentName)) {
            context.report({messageId: 'noSxComponents', node})
          }
        }
      },
    }
  },
})
