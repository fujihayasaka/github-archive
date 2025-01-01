// work around so we get the right version of the library
// if we take `scan` from root of the package, webpack will remove it
// the other alternative was `react-scan/dist/auto.global` but `dangerouslyForceRunInProduction` isn't fixed in 0.0.54
import {scan} from 'react-scan/dist/index'

if (typeof window !== 'undefined') {
  scan({dangerouslyForceRunInProduction: true})
}
