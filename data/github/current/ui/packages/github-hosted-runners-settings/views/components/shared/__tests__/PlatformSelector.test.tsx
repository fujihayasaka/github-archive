import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlatformOsType, platformOptions} from '../../../../types/platform'
import {PlatformSelector} from '../PlatformSelector'
import {getImage, getMachineSpec} from '../../../../test-utils/mock-data'
import {MachineSpecArchitecture} from '../../../../types/machine-spec'

const machineSpecs = [
  getMachineSpec(),
  getMachineSpec({
    id: 'arm-4-core',
    architecture: MachineSpecArchitecture.ARM64,
  }),
]

const images = {
  github: [getImage()],
  partner: [
    getImage({
      osType: PlatformOsType.Linux,
      architecture: MachineSpecArchitecture.ARM64,
      displayName: 'Arm Linux Image',
    }),
    getImage({
      osType: PlatformOsType.Windows,
      architecture: MachineSpecArchitecture.ARM64,
      displayName: 'Arm Windows Image',
    }),
  ],
}

describe('PlatformSelector', () => {
  test('renders unfiltered', () => {
    render(
      <PlatformSelector
        value={platformOptions[0]}
        setValue={jest.fn()}
        isCustomImageUploadingEnabled
        machineSpecs={machineSpecs}
        images={images}
        onValidationError={jest.fn()}
      />,
    )

    const platformRadioGroup = screen.getByTestId('platform-input')
    expect(platformRadioGroup).toBeInTheDocument()

    const radioGroup = within(platformRadioGroup).getByRole('group')
    expect(radioGroup).toHaveTextContent('Platform')

    // all radios are rendered
    const radios = within(platformRadioGroup).getAllByRole('radio')
    expect(radios).toHaveLength(platformOptions.length)

    // renders a radio and label for each radio button
    for (const option of platformOptions) {
      const radio = within(platformRadioGroup).getByTestId(`platform-option-radio-${option.id}`)
      expect(radio).toBeInTheDocument()
      expect(radio).toHaveAttribute('value', option.id)

      const label = within(platformRadioGroup).getByTestId(`platform-option-label-${option.id}`)
      expect(label).toBeInTheDocument()
      expect(label).toHaveTextContent(option.displayName)
    }

    const saveButton = screen.getByTestId('platform-save-button')
    expect(saveButton).toBeInTheDocument()
  })
})
