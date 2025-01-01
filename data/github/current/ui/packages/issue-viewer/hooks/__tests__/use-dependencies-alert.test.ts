import {renderHook, act} from '@testing-library/react'
import {useDependencyAlerts} from '../use-dependencies-alert'

describe('useDependencyAlerts', () => {
  it('should initialize with empty alerts', () => {
    const {result} = renderHook(() => useDependencyAlerts())

    expect(result.current.alerts).toEqual([])
  })

  it('should reset alerts', () => {
    const {result} = renderHook(() => useDependencyAlerts())

    // Add an alert first
    act(() => {
      result.current.setAlerts([{title: 'Test Alert', body: 'Test body'}])
    })

    expect(result.current.alerts.length).toBe(1)

    // Reset alerts
    act(() => {
      result.current.resetAlerts()
    })

    expect(result.current.alerts).toEqual([])
  })

  it('should handle breadth alert for blocked-by relationship', () => {
    const {result} = renderHook(() => useDependencyAlerts())

    act(() => {
      result.current.setAlertsFromErrors([new Error('cannot have more than 5 blocked-by relations')])
    })

    expect(result.current.alerts.length).toBe(1)
    expect(result.current.alerts[0]?.title).toBe('Dependency limit reached')
    expect(result.current.alerts[0]?.body).toContain('limit of 5 "blocked by" relationships')
  })

  it('should handle breadth alert for blocking relationship', () => {
    const {result} = renderHook(() => useDependencyAlerts())

    act(() => {
      result.current.setAlertsFromErrors([new Error('cannot have more than 10 blocking relations')])
    })

    expect(result.current.alerts.length).toBe(1)
    expect(result.current.alerts[0]?.title).toBe('Dependency limit reached')
    expect(result.current.alerts[0]?.body).toContain('limit of 10 "blocking" relationships')
  })

  it('should handle permission alert', () => {
    const {result} = renderHook(() => useDependencyAlerts())

    act(() => {
      result.current.setAlertsFromErrors([new Error('user does not have the correct permissions to execute')])
    })

    expect(result.current.alerts.length).toBe(1)
    expect(result.current.alerts[0]?.title).toBe('Access denied')
    expect(result.current.alerts[0]?.body).toContain('You do not have permission')
  })

  it('should handle circular dependency alert', () => {
    const {result} = renderHook(() => useDependencyAlerts())

    act(() => {
      result.current.setAlertsFromErrors([
        new Error('this dependency would create a cycle where the target is already blocked by the source'),
      ])
    })

    expect(result.current.alerts.length).toBe(1)
    expect(result.current.alerts[0]?.title).toBe('Circular dependency')
    expect(result.current.alerts[0]?.body).toContain('issue may not be blocked by an issue that it is already blocking')
  })

  it('should handle unexpected errors', () => {
    const {result} = renderHook(() => useDependencyAlerts())

    act(() => {
      result.current.setAlertsFromErrors([new Error('Some unexpected error occurred')])
    })

    expect(result.current.alerts.length).toBe(1)
    expect(result.current.alerts[0]?.title).toBe('Unexpected error')
    expect(result.current.alerts[0]?.body).toContain('An unexpected error occurred')
    expect(result.current.alerts[0]?.body).toContain('Some unexpected error occurred')
  })

  it('should handle multiple errors', () => {
    const {result} = renderHook(() => useDependencyAlerts())

    act(() => {
      result.current.setAlertsFromErrors([
        new Error('cannot have more than 5 blocked-by relations'),
        new Error('user does not have the correct permissions to execute'),
      ])
    })

    expect(result.current.alerts.length).toBe(2)
    expect(result.current.alerts[0]?.title).toBe('Dependency limit reached')
    expect(result.current.alerts[1]?.title).toBe('Access denied')
  })

  it('should append alerts to existing ones', () => {
    const {result} = renderHook(() => useDependencyAlerts())

    // Add an initial alert
    act(() => {
      result.current.setAlerts([{title: 'Initial Alert', body: 'Initial body'}])
    })

    // Add more alerts through error handling
    act(() => {
      result.current.setAlertsFromErrors([new Error('cannot have more than 5 blocked-by relations')])
    })

    expect(result.current.alerts.length).toBe(2)
    expect(result.current.alerts[0]?.title).toBe('Initial Alert')
    expect(result.current.alerts[1]?.title).toBe('Dependency limit reached')
  })

  it('should directly set alerts', () => {
    const {result} = renderHook(() => useDependencyAlerts())

    const newAlerts = [
      {title: 'Alert 1', body: 'Body 1'},
      {title: 'Alert 2', body: 'Body 2'},
    ]

    act(() => {
      result.current.setAlerts(newAlerts)
    })

    expect(result.current.alerts).toEqual(newAlerts)
  })
})
