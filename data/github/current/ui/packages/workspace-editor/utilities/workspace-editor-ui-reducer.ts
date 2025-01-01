import type {SendAnalyticsEventFunction} from '../telemetry/interfaces'
import {setShowDiff} from './preferences'
import {focusedTaskQueryParam, panelQueryParam, removeQueryParam, setQueryParam} from './query-params'
import type {BannerType, DiffStyle} from './workspace-editor-types'

export const RightPanelType = {
  Chat: 'Chat',
  Suggestions: 'Suggestions',
  None: '',
} as const

export type RightPanelType = (typeof RightPanelType)[keyof typeof RightPanelType]

export interface WorkspaceEditorUIState {
  banner: BannerType
  diffStyle: DiffStyle
  rightPanel: RightPanelType
  rightPanelButton?: HTMLButtonElement | HTMLElement
  showDiff: boolean
}

export type WorkspaceEditorUIAction =
  | {type: 'CLOSE_RIGHT_PANEL'}
  | {
      type: 'OPEN_RIGHT_PANEL'
      rightPanel: WorkspaceEditorUIState['rightPanel']
      rightPanelButton: WorkspaceEditorUIState['rightPanelButton']
    }
  | {
      type: 'SET_DIFF_STYLE'
      diffStyle: WorkspaceEditorUIState['diffStyle']
    }
  | {
      type: 'SET_SHOW_DIFF'
      showDiff: WorkspaceEditorUIState['showDiff']
    }
  | {
      type: 'SET_BANNER'
      banner: WorkspaceEditorUIState['banner']
    }
  | {
      type: 'TOGGLE_RIGHT_PANEL'
      rightPanel: WorkspaceEditorUIState['rightPanel']
      rightPanelButton: WorkspaceEditorUIState['rightPanelButton']
    }

export function workspaceEditorUIReducer(
  sendEvent: SendAnalyticsEventFunction,
): (state: WorkspaceEditorUIState, action: WorkspaceEditorUIAction) => WorkspaceEditorUIState {
  return (state: WorkspaceEditorUIState, action: WorkspaceEditorUIAction) => {
    const {type, ...rest} = action

    /**
     * For defining logic for actions that do more than set state.
     */
    switch (type) {
      case 'CLOSE_RIGHT_PANEL': {
        removeQueryParam(panelQueryParam)
        removeQueryParam(focusedTaskQueryParam)
        state.rightPanelButton?.focus()
        return {...state, rightPanel: RightPanelType.None, rightPanelButton: undefined}
      }

      case 'OPEN_RIGHT_PANEL': {
        setQueryParam(panelQueryParam, action.rightPanel)
        return {...state, rightPanel: action.rightPanel, rightPanelButton: action.rightPanelButton}
      }

      case 'TOGGLE_RIGHT_PANEL': {
        if (state.rightPanel === action.rightPanel) {
          removeQueryParam(panelQueryParam)
          removeQueryParam(focusedTaskQueryParam)
          sendEvent('right-panel.close')
          return {...state, rightPanel: RightPanelType.None, rightPanelButton: undefined}
        } else {
          if (action.rightPanel !== RightPanelType.Suggestions) {
            removeQueryParam(focusedTaskQueryParam)
          }
          setQueryParam(panelQueryParam, action.rightPanel)
          sendEvent('right-panel.open', {new_panel: action.rightPanel})
          return {...state, rightPanel: action.rightPanel, rightPanelButton: action.rightPanelButton}
        }
      }
      case 'SET_DIFF_STYLE': {
        setShowDiff(true)
        return {...state, diffStyle: action.diffStyle, showDiff: true}
      }
      case 'SET_SHOW_DIFF': {
        setShowDiff(action.showDiff)
        return {...state, showDiff: action.showDiff}
      }
    }
    return {...state, ...rest}
  }
}
