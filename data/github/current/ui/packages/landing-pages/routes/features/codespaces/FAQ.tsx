import {FAQ} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function FAQSection() {
  return (
    <section id="faq">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <FAQ className="lp-FAQ">
          <FAQ.Heading>Frequently asked questions</FAQ.Heading>
          <FAQ.Item>
            <FAQ.Question>How does Codespaces work?</FAQ.Question>

            <FAQ.Answer>
              <p>
                A codespace is a development environment that’s hosted in the cloud. Customize your project for GitHub
                Codespaces by{' '}
                <a href="https://docs.github.com/codespaces/customizing-your-codespace/configuring-codespaces-for-your-project">
                  configuring dev container files
                </a>{' '}
                to your repository (often known as configuration-as-code), which creates a repeatable codespace
                configuration for all users of your project.
              </p>
              <p>
                GitHub Codespaces run on a various VM-based compute options hosted by GitHub.com, which you can
                configure from 2 core machines up to 32 core machines. Connect to your codespaces from the browser or
                locally using an IDE like Visual Studio Code or IntelliJ.
              </p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>How do I use Codespaces?</FAQ.Question>

            <FAQ.Answer>
              <p>There are a number of entry points to spin up a Codespaces environment, including:</p>
              <ul>
                <li>
                  A <a href="https://docs.github.com/codespaces/getting-started/quickstart">template</a>.
                </li>

                <li>
                  <a href="https://docs.github.com/codespaces/developing-in-codespaces/creating-a-codespace#creating-a-codespace">
                    Your repository
                  </a>{' '}
                  for new feature work
                </li>

                <li>
                  An{' '}
                  <a href="https://docs.github.com/codespaces/developing-in-codespaces/using-github-codespaces-for-pull-requests#opening-a-pull-request-in-codespaces">
                    open pull request
                  </a>{' '}
                  to explore work-in-progress
                </li>

                <li>A commit in the repository’s history to investigate a bug at a specific point in time</li>

                <li>
                  <a href="https://docs.github.com/codespaces/developing-in-codespaces/using-github-codespaces-in-visual-studio-code#creating-a-codespace-in-vs-code">
                    Visual Studio Code
                  </a>
                </li>

                <li>
                  In beta, can you also use your{' '}
                  <a href="https://docs.github.com/codespaces/developing-in-a-codespace/using-github-codespaces-in-your-jetbrains-ide">
                    JetBrains IDE
                  </a>{' '}
                  or{' '}
                  <a href="https://docs.github.com/codespaces/developing-in-a-codespace/getting-started-with-github-codespaces-for-machine-learning">
                    JupyterLab
                  </a>
                </li>
              </ul>
              <p>
                Learn more about how to use Codespaces in our{' '}
                <a href="https://docs.github.com/codespaces/overview">documentation</a>.
              </p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>Is Codespaces available for individual developers?</FAQ.Question>

            <FAQ.Answer>
              <p>
                Codespaces is available for developers in every organization, and under the control of the organization
                who pays for the user’s codespace. All personal (individual) GitHub.com accounts include a quota of free
                usage each month, which organizations can enable (see the next question) for their private and internal
                repositories. GitHub will provide users in the free plan 120 core hours or 60 hours of run time on a 2
                core codespace, plus 15 GB of storage each month. See how it’s balanced on the{' '}
                <a href="https://github.com/settings/billing">billing page</a>.
              </p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>Is Codespaces available for teams and companies?</FAQ.Question>

            <FAQ.Answer>
              <p>
                Codespaces is available for teams and companies, but needs to be enabled first in an organization’s
                settings. Teams and companies can select which repositories and users have access to Codespaces for
                added security and permissioning control. Learn how to{' '}
                <a href="https://docs.github.com/codespaces/managing-codespaces-for-your-organization/enabling-github-codespaces-for-your-organization">
                  enable Codespaces in an organization in our docs
                </a>
                .
              </p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>How much does Codespaces cost?</FAQ.Question>

            <FAQ.Answer>
              <p>
                Codespaces is free for individual use up to 60 hours a month and comes with simple, pay-as-you-go
                pricing after that. It’s also available for organizations with pay-as-you-go pricing and has pricing
                controls so any company or team can determine how much they want to spend a month. Learn more about
                Codespaces pricing for organizations{' '}
                <a href="https://docs.github.com/billing/managing-billing-for-github-codespaces/about-billing-for-github-codespaces">
                  here
                </a>
                .
              </p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>Can I self-host Codespaces?</FAQ.Question>

            <FAQ.Answer>
              <p>Codespaces cannot be self-hosted.</p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>How do I access Codespaces with LinkedIn Learning?</FAQ.Question>

            <FAQ.Answer>
              <p>
                You can use Codespaces directly through LinkedIn Learning. LinkedIn Learning offers 50+ courses across
                six of the most popular coding languages, as well as data science and machine learning. These courses
                are integrated with Codespaces, so you can get hands-on practice anytime, from any machine via LinkedIn.
                These courses will be unlocked on LinkedIn Learning for free through Feb. 2023. Learn more about
                LinkedIn Learning and GitHub Codespaces{' '}
                <a href="https://learning.linkedin.com/product/hands-on-practice">here</a>.
              </p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>How do I enable Codespaces on GitHub?</FAQ.Question>

            <FAQ.Answer>
              <p>
                Codespaces is on by default for developers with a GitHub free account. If you belong to an organization,
                there may be a policy that prevents cloning—but if you can clone a repository, you will be able to start
                using Codespaces. Organizations will also need to pay for, enable, and manage their Codespaces
                instances.
              </p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>Is Codespaces available for students?</FAQ.Question>

            <FAQ.Answer>
              <p>
                Codespaces is available for free to students as part of the GitHub Student Developer Pack. Learn more
                about how to sign up and start using Codespaces and other GitHub products{' '}
                <a href="https://education.github.com/pack">here</a>.
              </p>
            </FAQ.Answer>
          </FAQ.Item>

          <FAQ.Item>
            <FAQ.Question>Is Codespaces available for open source maintainers?</FAQ.Question>

            <FAQ.Answer>
              <p>
                Codespaces provides both maintainers and contributors with{' '}
                <a href="https://docs.github.com/billing/managing-billing-for-github-codespaces/about-billing-for-github-codespaces#monthly-included-storage-and-core-hours-for-personal-accounts">
                  generous free monthly usage
                </a>
                .
              </p>
            </FAQ.Answer>
          </FAQ.Item>
        </FAQ>
      </div>
    </section>
  )
}
