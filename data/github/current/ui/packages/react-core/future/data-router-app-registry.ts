import {DeferredRegistry} from '../deferred-registry'
import type {DataRouterApplication} from './data-router-application'

export type DataRouterAppRegistrationFn = DataRouterApplication<string>['registration']

export type DataRouterAppRegistrationObject = {type: 'DataRouterApp'; registration: DataRouterAppRegistrationFn}

export function createDataRouterAppRegistration(
  registration: DataRouterAppRegistrationFn,
): DataRouterAppRegistrationObject {
  return {
    type: 'DataRouterApp',
    registration,
  }
}

export const reactDataRouterAppDeferredRegistry = new DeferredRegistry<DataRouterAppRegistrationObject>()

export async function getReactDataRouterApp(appName: string) {
  return reactDataRouterAppDeferredRegistry.getRegistration(appName).promise
}
