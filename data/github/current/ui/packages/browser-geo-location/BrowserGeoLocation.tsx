import {useState} from 'react'

export interface BrowserGeoLocationProps {
  locationSharedInputId: string
  latitudeInputId: string
  longitudeInputId: string
}

export function BrowserGeoLocation({
  locationSharedInputId,
  latitudeInputId,
  longitudeInputId,
}: BrowserGeoLocationProps) {
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle')

  const handleShareLocationClick = async (event: React.MouseEvent<HTMLButtonElement>) => {
    event.preventDefault()
    if (status === 'loading') return
    setStatus('loading')
    const locationSharedInput = document.getElementById(locationSharedInputId) as HTMLInputElement

    try {
      if (navigator.geolocation) {
        const position = await new Promise<GeolocationPosition>((resolve, reject) => {
          navigator.geolocation.getCurrentPosition(resolve, reject)
        })

        const latitude = position.coords.latitude
        const longitude = position.coords.longitude

        const latitudeField = document.getElementById(latitudeInputId) as HTMLInputElement
        const longitudeField = document.getElementById(longitudeInputId) as HTMLInputElement

        if (latitudeField) latitudeField.value = latitude.toString()
        if (longitudeField) longitudeField.value = longitude.toString()

        if (locationSharedInput) locationSharedInput.value = 'true'
        setStatus('success')
      } else {
        if (locationSharedInput) locationSharedInput.value = 'false'
        setStatus('error')
      }
    } catch {
      if (locationSharedInput) locationSharedInput.value = 'false'
      setStatus('error')
    }
  }

  const getButtonText = () => {
    switch (status) {
      case 'loading':
        return 'Getting location...'
      case 'success':
        return '✓ Location shared'
      case 'error':
        return 'Error getting location. Try again?'
      default:
        return 'Share Location'
    }
  }

  const getButtonClasses = () => {
    const baseClasses = 'btn float-left mt-2'

    switch (status) {
      case 'success':
        return `${baseClasses} btn-success`
      case 'error':
        return `${baseClasses} btn-danger`
      default:
        return `${baseClasses} btn-primary`
    }
  }

  return (
    <button
      type="button"
      className={getButtonClasses()}
      onClick={handleShareLocationClick}
      disabled={status === 'loading' || status === 'success'}
      aria-busy={status === 'loading'}
    >
      {getButtonText()}
    </button>
  )
}
