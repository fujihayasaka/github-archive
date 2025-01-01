/**
 * sync changes with types in dotcom
 * /workspaces/github/ui/packages/workbench/targeted-edits/types.ts
 */

export type BridgeMessage =
  | {
      type: 'spark:designer:bridge:enable'
    }
  | {
      type: 'spark:designer:bridge:disable'
    }
  | {
      type: 'spark:designer:bridge:deselect'
    }
  | {
      type: 'spark:designer:bridge:update-class-name'
      location: {
        filePath: string
        line: number
        column: number
      }
      className: string
      replace: boolean
    }
  | {
      type: 'spark:designer:bridge:update-element-token'
      location: {
        filePath: string
        line: number
        column: number
      }
      name: string
      value: string
    }
  | {
      type: 'spark:designer:bridge:update-theme-token'
      token: 'primary' | 'primary-foreground' | 'secondary' | 'secondary-foreground' | 'background' | 'radius'
      value: string
    }

type ElementLocation = {
  start: {
    filePath: string
    line: number
    column: number
  }
  end: {
    filePath: string
    line: number
    column: number
  }
}

export type ElementPayload = {
  tag: string
  component: {
    location: null | ElementLocation
  }
  props: Record<string, string | number | boolean>
  location: null | ElementLocation
  instanceCount: number
  position: {
    top: number
    left: number
    width: number
    height: number
  }
  editable: boolean
  text: string | null
  class: string | null
}

export type HostMessage =
  | {
      type: 'spark:designer:host:element:selected'
      element: ElementPayload
    }
  | {
      type: 'spark:designer:bridge:element:updated'
      element: ElementPayload
    }
  | {
      type: 'spark:designer:bridge:element:deselected'
      element: null
    }
