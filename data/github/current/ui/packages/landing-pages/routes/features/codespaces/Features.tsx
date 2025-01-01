import {River, Image, Text, Heading, RiverBreakout, Timeline, AnimationProvider} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function FeaturesSection() {
  return (
    <section id="features">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <AnimationProvider>
          <River className="fp-River">
            <River.Visual className="fp-River-visual">
              <Image
                src="/images/modules/site/codespaces/fp24/features-river-1.webp"
                alt="Graphic featuring three key security features of GitHub Codespaces. Each feature is listed in a black rectangle with a green checkmark icon to the up. The features include 'Isolated Environments,' 'Access Control,' and 'Cost Control.' The background transitions from green at the top to teal at the bottom"
                loading="lazy"
              />
            </River.Visual>

            <River.Content className="fp-River-content" animate="slide-in-up">
              <Heading as="h2" size="4">
                Secure by design
              </Heading>

              <Text>
                Created with security in mind, Codespaces provides a secure development environment through its built-in
                capabilities and native integration with the GitHub platform.
              </Text>
            </River.Content>
          </River>

          <River className="fp-River">
            <River.Visual className="fp-River-visual">
              <Image
                src="/images/modules/site/codespaces/fp24/features-river-2.webp"
                alt="Screenshot showing a snippet of a JSON configuration file used in GitHub Codespaces. The file defines settings for a development environment, including specifying an image with the key 'image' set to ghcr.io/github/github/dev_image:latest. It also includes configurations like 'forwardPorts' for automatically forwarding specific ports (such as 80, 2222, 3003, and others), a terminal setting with the key 'terminal.integrated.shell.linux' set to /bin/bash, and a 'postCreateCommand' to run npm install after setup. The background features a gradient from green to teal."
                loading="lazy"
              />
            </River.Visual>

            <River.Content className="fp-River-content" animate="slide-in-up">
              <Heading as="h2" size="4">
                Collaborate where you code
              </Heading>

              <Text>Codespaces provides a shared development environment and removes the need for complex setups.</Text>
            </River.Content>
          </River>
        </AnimationProvider>

        <Spacer size="64px" size1012="128px" />

        <RiverBreakout className="fp-RiverBreakout">
          <RiverBreakout.A11yHeading>Customize your Codespaces</RiverBreakout.A11yHeading>

          <RiverBreakout.Visual>
            <Image
              className="fp-RiverBreakoutVisualImage"
              src="/images/modules/site/codespaces/fp24/features-river-breakout.webp"
              alt="Screenshot of a GitHub Codespaces environment titled 'codespaces-demo.' The interface shows a file explorer on the left side with various files and folders, including .devcontainer, build.css, and setup-devcontainer.sh. The main editor displays the content of the build.css file, with CSS code specifying styles for elements like .main and .container > header. On the right side, a panel allows the user to select a machine configuration, with options for 8-core, 16-core, and 32-core setups, indicating different levels of RAM and storage. The background features a gradient from teal to green."
              loading="lazy"
            />
          </RiverBreakout.Visual>

          <RiverBreakout.Content
            className="fp-RiverBreakout-content"
            trailingComponent={() => (
              <Timeline>
                <Timeline.Item>
                  <em>Start coding instantly from anywhere in the world.</em> Switching projects? Grab a new machine
                  from the cloud that’s preconfigured for that project. Your settings travel with you.
                </Timeline.Item>

                <Timeline.Item>
                  <em>Tabs or spaces? Monokai or Solarized? Prettier or Beautify? It’s up to you.</em> Control every
                  nerdy detail only you care about with your own dotfiles repository.
                </Timeline.Item>
              </Timeline>
            )}
          >
            <Text>
              <em>Your space, your way.</em> Codespaces is a home away from home for your code that feels just like your
              usual machine.
              <Image
                className="lp-FeaturesLogos"
                src="/images/modules/site/codespaces/fp24/features-logos.webp"
                width={496}
                alt="Logos for popular development tools and extensions, including ES Lint, IntelliCode, Prettier, Live Server, Copilot, Docker, GitLens, and Debugger for Java."
                loading="lazy"
              />
            </Text>
          </RiverBreakout.Content>
        </RiverBreakout>

        <Spacer size="64px" size1012="128px" />

        <AnimationProvider>
          <River className="fp-River">
            <River.Visual className="fp-River-visual">
              <Image
                src="/images/modules/site/codespaces/fp24/features-river-3.webp"
                alt="Screenshot of a GitHub Codespaces environment showing a browser window with the text 'hello, world!1!!' displayed. Below the browser, there is a 'Ports' panel listing several active ports, including 'web (3000),' 'hmr (55306),' 'mysql (3306),' and 'api (3001).' A context menu is open with options like 'Open in Browser,' 'Set Port Label,' 'Copy Local Address,' and 'Make Public,' with the cursor hovering over the 'Make Public' option. The background features a gradient from blue to green."
                loading="lazy"
              />
            </River.Visual>

            <River.Content className="fp-River-content" animate="slide-in-up">
              <Heading as="h2" size="4">
                Browser preview and port forwarding
              </Heading>

              <Text>
                Preview your changes and get feedback from teammates by sharing ports within the scope allowed by
                policy.
              </Text>
            </River.Content>
          </River>

          <River className="fp-River">
            <River.Visual className="fp-River-visual">
              <Image
                src="/images/modules/site/codespaces/fp24/features-river-4.webp"
                alt="Screenshot showing a list of three active GitHub Codespaces environments.The first environment is titled 'mn-webgl-sandbox' under the branch 'webgl-changes,' and shows zero down arrows and six up arrows indicating changes. The second environment is titled 'ui refactoring' under the branch 'layout-refactor,' showing four down arrows and two up arrows. The third environment is titled 'psychic space doodle' under the branch 'node-extensions,' with one down arrow and five up arrows. Each environment is marked as 'Active' with a green dot and a small avatar representing the user associated with the environment. The background features a gradient from teal to green."
                loading="lazy"
              />
            </River.Visual>

            <River.Content className="fp-River-content" animate="slide-in-up">
              <Heading as="h2" size="4">
                Onboard faster
              </Heading>

              <Text>
                Quickly spin up a codespace with only an IDE or browser and a GitHub account. With a few configuration
                files, you can give your developers an instant, fully configured, and secure development environment so
                they can start coding immediately.
              </Text>
            </River.Content>
          </River>
        </AnimationProvider>
      </div>
    </section>
  )
}
