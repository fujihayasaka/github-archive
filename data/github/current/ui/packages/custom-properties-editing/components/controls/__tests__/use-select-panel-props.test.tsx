// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {renderHook} from '@testing-library/react'

import {getDisplayAnchorLabel, useSelectPanelProps} from '../use-select-panel-props'

type HookProps = Parameters<typeof useSelectPanelProps>[0]
const sampleProps: HookProps = {
  propertyName: 'env',
  defaultValue: null,
  allowedValues: ['test', 'prod'],
  mixed: false,
  currentSelection: [],
}

describe('useSelectPanelProps', () => {
  describe('single select mode', () => {
    describe('optional property', () => {
      const initialProps: HookProps = {
        ...sampleProps,
        singleSelectMode: true,
      }

      it('no value selected', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps})

        expect(result.current.items).toMatchObject([
          {groupId: 'empty', text: '(Empty)', selected: true},
          {groupId: 'options', text: 'test', selected: false},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })

      it('value selected', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps: {...initialProps, currentSelection: ['test']}})

        expect(result.current.items).toMatchObject([
          {groupId: 'empty', text: '(Empty)', selected: false},
          {groupId: 'options', text: 'test', selected: true},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })

      it('mixed state', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps: {...initialProps, mixed: true}})

        expect(result.current.items).toMatchObject([
          {groupId: 'empty', text: '(Empty)', selected: false},
          {groupId: 'options', text: 'test', selected: false},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })
    })

    describe('required property', () => {
      const initialProps: HookProps = {
        ...sampleProps,
        defaultValue: 'test',
        singleSelectMode: true,
      }

      it('no value selected', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps})

        expect(result.current.items).toMatchObject([
          {groupId: 'default', text: 'Default (test)', selected: true},
          {groupId: 'options', text: 'test', selected: false},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })

      it('value selected', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps: {...initialProps, currentSelection: ['test']}})

        expect(result.current.items).toMatchObject([
          {groupId: 'default', text: 'Default (test)', selected: false},
          {groupId: 'options', text: 'test', selected: true},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })

      it('mixed state', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps: {...initialProps, mixed: true}})

        expect(result.current.items).toMatchObject([
          {groupId: 'default', text: 'Default (test)', selected: false},
          {groupId: 'options', text: 'test', selected: false},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })
    })
  })

  describe('multi select mode', () => {
    describe('optional property', () => {
      const initialProps: HookProps = {
        ...sampleProps,
        singleSelectMode: false,
      }

      it('no value selected', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps})

        expect(result.current.items).toMatchObject([
          {groupId: 'options', text: 'test', selected: false},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })

      it('value selected', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps: {...initialProps, currentSelection: ['test']}})

        expect(result.current.items).toMatchObject([
          {groupId: 'options', text: 'test', selected: true},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })

      it('mixed state', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps: {...initialProps, mixed: true}})

        expect(result.current.items).toMatchObject([
          {groupId: 'options', text: 'test', selected: false},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })
    })

    describe('required property', () => {
      const initialProps: HookProps = {
        ...sampleProps,
        defaultValue: ['test'],
        singleSelectMode: false,
      }

      it('no value selected', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps})

        expect(result.current.items).toMatchObject([
          {groupId: 'default', text: 'Default (test)', selected: true},
          {groupId: 'options', text: 'test', selected: false},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })

      it('value selected', () => {
        const {result} = renderHook(useSelectPanelProps, {
          initialProps: {...initialProps, currentSelection: ['test', 'prod']},
        })

        expect(result.current.items).toMatchObject([
          {groupId: 'default', text: 'Default (test)', selected: false},
          {groupId: 'options', text: 'test', selected: true},
          {groupId: 'options', text: 'prod', selected: true},
        ])
      })

      it('mixed state', () => {
        const {result} = renderHook(useSelectPanelProps, {initialProps: {...initialProps, mixed: true}})

        expect(result.current.items).toMatchObject([
          {groupId: 'default', text: 'Default (test)', selected: false},
          {groupId: 'options', text: 'test', selected: false},
          {groupId: 'options', text: 'prod', selected: false},
        ])
      })
    })
  })
})

describe('getDisplayAnchorLabel', () => {
  describe('text value', () => {
    it('no value', () => expect(getDisplayAnchorLabel('', null, false)).toEqual('Choose an option'))
    it('mixed', () => expect(getDisplayAnchorLabel('', null, true)).toEqual('(Mixed)'))
    it('default', () => expect(getDisplayAnchorLabel('', 'test', false)).toEqual('Default (test)'))
    it('selected', () => {
      expect(getDisplayAnchorLabel('test', 'default', false)).toEqual('test')
      expect(getDisplayAnchorLabel('test', null, false)).toEqual('test')
    })
  })

  describe('list of values', () => {
    it('no value', () => expect(getDisplayAnchorLabel([], null, false)).toEqual('Choose an option'))
    it('mixed', () => expect(getDisplayAnchorLabel([], null, true)).toEqual('(Mixed)'))
    it('default single', () => expect(getDisplayAnchorLabel([], ['test'], false)).toEqual('Default (test)'))
    it('default multiple', () => expect(getDisplayAnchorLabel([], ['a', 'b'], false)).toEqual('Default (2 selected)'))
    it('1 selected', () => {
      expect(getDisplayAnchorLabel(['test'], ['default'], false)).toEqual('test')
      expect(getDisplayAnchorLabel(['test'], null, false)).toEqual('test')
    })
    it('Multiple selected', () => {
      expect(getDisplayAnchorLabel(['a', 'b'], ['default'], false)).toEqual('2 selected')
      expect(getDisplayAnchorLabel(['a', 'b'], null, false)).toEqual('2 selected')
    })
  })
})
