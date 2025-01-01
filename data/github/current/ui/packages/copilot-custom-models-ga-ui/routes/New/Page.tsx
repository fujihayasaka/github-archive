import {Box, Button, FormControl, Heading, Radio, RadioGroup, Text, Textarea, TextInput, Token} from '@primer/react'
import {Links} from '../../components/Links'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import type {RoutePayload} from './types'
import {FormSection} from './components/FormSection'
import {FileCodeIcon, GearIcon, RepoIcon, TriangleDownIcon} from '@primer/octicons-react'
import {InsetBanner} from './components/InsetBanner'
import {theme} from '../../theme'
import {useState} from 'react'

// TODO: AnchoredOverlay over the Enabled button
// TODO: Language picker + token adding/removing?
export function New() {
  const routePayload = useRoutePayload<RoutePayload>()
  const [description, setDescription] = useState('')

  return (
    <Box
      sx={{
        alignItems: 'center',
        display: 'flex',
        flexDirection: 'column',
        gap: '24px',
        justifyContent: 'center',
        mt: '40px',
        width: '100%',
      }}
    >
      <Box sx={{display: 'flex', flexDirection: 'column', gap: '8px', justifyContent: 'center', width: '100%'}}>
        <Heading as="h3" sx={{color: theme.color.fgDefault, ...theme.typography.deprecated.heading.h3}}>
          Prepare your training data
        </Heading>
        <Text sx={{color: theme.color.fgMuted, ...theme.typography.deprecated.textNormal}}>
          Choose data sources to train your model on. The model doesn&apos;t &lsquo;memorize&rsquo; your data but uses
          it to learn patterns and behaviors. If you need more informations you can learn more about best practices.
        </Text>
      </Box>

      <Box
        sx={{
          alignItems: 'center',
          border: theme.border,
          borderRadius: '6px',
          display: 'flex',
          flexDirection: 'row',
          gap: '12px',
          justifyContent: 'space-between',
          p: '12px',
          width: '100%',
        }}
      >
        <Box sx={{display: 'flex', flexDirection: 'column', gap: '2px', justifyContent: 'center', width: '100%'}}>
          <Heading as="h4" sx={{color: theme.color.fgDefault, ...theme.typography.body.mediumBold}}>
            Start with a template
          </Heading>
          <Text sx={{color: theme.color.fgMuted, ...theme.typography.body.small}}>
            Templates analyze your existing data and will suggest data sources for your model. This can take a few
            minutes.
          </Text>
        </Box>

        <Button variant="default">Use template</Button>
      </Box>

      <Box
        as="form"
        sx={{display: 'flex', flexDirection: 'column', gap: '24px', justifyContent: 'center', width: '100%'}}
      >
        <FormSection icon={GearIcon} title="General">
          <FormControl required>
            <FormControl.Label>Name</FormControl.Label>
            <TextInput sx={{width: '100%'}} />
          </FormControl>

          <FormControl>
            <FormControl.Label>Description</FormControl.Label>
            <Textarea
              onChange={e => setDescription(e.target.value)}
              rows={2}
              sx={{width: '100%'}}
              value={description}
            />
            {description.length > 500 && (
              <FormControl.Validation variant="error">
                Description is too long. The limit is 500 characters.
              </FormControl.Validation>
            )}
            <FormControl.Caption>{description.length} / 500 characters</FormControl.Caption>
          </FormControl>

          <Box
            sx={{
              border: theme.border,
              borderRadius: '6px',
              display: 'flex',
              flexDirection: 'column',
              width: '100%',
            }}
          >
            <Box
              sx={{alignItems: 'flex-start', display: 'flex', gap: '40px', justifyContent: 'space-between', p: '12px'}}
            >
              <Box sx={{display: 'flex', flexDirection: 'column', gap: '2px', width: '100%'}}>
                <Heading as="h5" sx={{color: theme.color.fgDefault, ...theme.typography.deprecated.textBold}}>
                  Include data from developer telemetry
                </Heading>
                <Text sx={{color: theme.color.fgMuted, ...theme.typography.deprecated.textSmall}}>
                  Make your training data stronger by including telemetry.
                </Text>
              </Box>

              <Button trailingVisual={TriangleDownIcon}>Enabled</Button>
            </Box>

            <InsetBanner>
              Teams that train on telemetry see an{' '}
              <Text as="span" sx={{fontWeight: 'bold'}}>
                x% improvement
              </Text>{' '}
              in acceptance rates over baseline models
            </InsetBanner>
          </Box>

          <Box sx={{display: 'flex', justifyContent: 'flex-end', width: '100%'}}>
            <Button variant="primary">Next</Button>
          </Box>
        </FormSection>

        <FormSection
          icon={RepoIcon}
          subtitle="Choose which repositories you want to train your model on, we encourage you use this is you have proprietary APIs or domain-specific patterns."
          title="Select repositories"
        >
          <Box
            sx={{
              border: theme.border,
              borderRadius: '6px',
              display: 'flex',
              flexDirection: 'column',
              width: '100%',
            }}
          >
            <RadioGroup name="select-repositories">
              <FormControl sx={{p: '12px'}}>
                <Radio value="all" />
                <FormControl.Label>All repositories</FormControl.Label>
                <FormControl.Caption>
                  Target all repositories. This may result in a larger dataset but could dilute relevance for specific
                  coding practices.
                </FormControl.Caption>
              </FormControl>
              <FormControl sx={{borderTop: theme.border, mt: '0px !important', p: '12px'}}>
                <Radio value="selected" />
                <FormControl.Label>Select repositories</FormControl.Label>
                <FormControl.Caption>Manually select each repository</FormControl.Caption>
              </FormControl>
              <FormControl sx={{borderTop: theme.border, mt: '0px !important', p: '12px'}}>
                <Radio value="active" />
                <FormControl.Label>Repositories with high activity or commits in the last 6 months</FormControl.Label>
                <FormControl.Caption>
                  <Box sx={{display: 'flex', flexDirection: 'column', gap: '8px'}}>
                    <span>Recommended repositories based on usage</span>
                    <Button size="small" sx={{width: 'fit-content !important'}} variant="link">
                      View 10 matching repositories
                    </Button>
                  </Box>
                </FormControl.Caption>
              </FormControl>
              <FormControl sx={{borderTop: theme.border, mt: '0px !important', p: '12px'}}>
                <Radio value="filtered" />
                <FormControl.Label>Filter repositories</FormControl.Label>
                <FormControl.Caption>
                  <Box sx={{display: 'flex', flexDirection: 'column', gap: '10px'}}>
                    <span>Dynamically target repositories by property</span>
                    <Button size="small" sx={{width: 'fit-content !important'}} variant="default">
                      <Text sx={{color: theme.color.fgMuted}}>Filters:</Text> 0 set
                    </Button>
                  </Box>
                </FormControl.Caption>
              </FormControl>
              <FormControl sx={{borderTop: theme.border, mt: '0px !important', p: '12px'}}>
                <Radio value="none" />
                <FormControl.Label>No repositories</FormControl.Label>
                <FormControl.Caption>Continue with telemetry-only fine tuning.</FormControl.Caption>
              </FormControl>
            </RadioGroup>

            <InsetBanner>
              Choose repositories that have high usage and include code that is critical for developers.
            </InsetBanner>
          </Box>

          <Box sx={{display: 'flex', justifyContent: 'flex-end', width: '100%'}}>
            <Button variant="primary">Next</Button>
          </Box>
        </FormSection>

        <FormSection
          icon={FileCodeIcon}
          subtitle="Targeting languages filters the training data to those languages. This can help reduce data size and make a more targeted custom model."
          title="Specify languages"
        >
          <Box
            sx={{
              border: theme.border,
              borderRadius: '6px',
              display: 'flex',
              flexDirection: 'column',
              width: '100%',
            }}
          >
            <Box sx={{display: 'flex', flexDirection: 'column', gap: '16px', p: '12px', width: '100%'}}>
              <Text sx={{color: theme.color.fgDefault, ...theme.typography.deprecated.textBold}}>
                Filter repository data by language
              </Text>

              <TextInput placeholder="Search languages" sx={{width: '100%'}} />

              <Text sx={{color: theme.color.fgMuted, ...theme.typography.deprecated.textSmall}}>
                If this is left empty, we will use all files in your repositories to train your model.
              </Text>

              <Box sx={{display: 'flex', gap: '16px', width: '100%'}}>
                <Text sx={{color: theme.color.fgDefault, ...theme.typography.deprecated.textBold}}>
                  Detected languages:
                </Text>

                <Box sx={{display: 'flex', gap: '8px'}}>
                  <Token text="js" />
                  <Token text="jsx" />
                  <Token text="vue" />
                </Box>
              </Box>
            </Box>

            <InsetBanner>
              Only 3 repositories contain significant{' '}
              <Text as="span" sx={{fontWeight: 'bold'}}>
                JavaScript
              </Text>{' '}
              code. Consider expanding your language filter for better coverage.
            </InsetBanner>
          </Box>

          <Box sx={{display: 'flex', justifyContent: 'flex-end', width: '100%'}}>
            <Button variant="primary">Validate and continue</Button>
          </Box>
        </FormSection>
      </Box>

      <Links {...routePayload} />
    </Box>
  )
}
