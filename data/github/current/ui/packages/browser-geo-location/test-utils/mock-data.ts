import type {BrowserGeoLocationProps} from '../BrowserGeoLocation'

export function getBrowserGeoLocationProps(): BrowserGeoLocationProps {
  return {
    locationSharedInputId: 'location-shared-input',
    latitudeInputId: 'latitude-input',
    longitudeInputId: 'longitude-input',
  }
}
