import {SectionIntro, River, Image, Text} from '@primer/react-brand'

import {Spacer} from '../components/Spacer'

export default function FeaturesSection() {
  return (
    <section id="features">
      <div className="fp-Section-container">
        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center">
          <SectionIntro.Heading size="3">Way more than grep.</SectionIntro.Heading>

          <SectionIntro.Description>
            GitHub code search can search across multiple repositories and is always up to date. It understands your
            code, and puts the most relevant results first.
          </SectionIntro.Description>
        </SectionIntro>

        <Spacer size="64px" size1012="96px" />

        <River className="fp-River" align="end">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/code-search/fp24/features-river-1.webp"
              alt="Screenshot showing the GitHub code search interface, with a search query for 'CodePoint' within the rust-lang/rust repository. The search results include various symbols and files related to 'CodePoint,' such as 'class CodePoint' in the library/wtf8.rs file, 'implementation CodePoint' in another file, and specific functions and fields like from_u32_unchecked and is_known_utf8. Each result has a 'Jump to' link on the right, allowing users to quickly navigate to the corresponding code. The background features a gradient from teal to green."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Text size="400" weight="semibold">
              <strong>Suggestions, completions, and more.</strong> Use the new search input to find symbols and
              files—and jump right to them.
            </Text>
          </River.Content>
        </River>

        <River className="fp-River">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/code-search/fp24/features-river-2.webp"
              alt="Screenshot of advanced GitHub search queries, including searches within the rust-lang organization, the tensorflow/tensorflow repository, and for 'validation' in Ruby or Python code. The background features a teal-to-green gradient."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Text size="400" weight="semibold">
              <strong>Powerful search syntax.</strong> Know exactly what you’re looking for? Express it with our
              powerful search operators.
            </Text>
          </River.Content>
        </River>

        <Spacer size="64px" size1012="128px" />

        <SectionIntro className="fp-SectionIntro" align="center">
          <SectionIntro.Heading size="3">Meet the all-new code view.</SectionIntro.Heading>

          <SectionIntro.Description>
            Dig deeper into complex codebases with tightly integrated search, code navigation and browsing.
          </SectionIntro.Description>
        </SectionIntro>

        <Spacer size="64px" size1012="96px" />

        <River className="fp-River" align="end">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/code-search/fp24/features-river-3.webp"
              alt="Screenshot of GitHub's code navigation panel showing details for the symbol CodePoint. It highlights the definition of CodePoint as a struct in the code and lists 24 references to it within the same file. The interface is dark-themed with a gradient background transitioning from green to blue."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Text size="400" weight="semibold">
              <strong>Code navigation.</strong> Instantly jump to definitions in over 10 languages. No setup required.
            </Text>
          </River.Content>
        </River>

        <River className="fp-River">
          <River.Visual className="fp-River-visual">
            <Image
              src="/images/modules/site/code-search/fp24/features-river-4.webp"
              alt="Screenshot of the file explorer in GitHub's code interface, showing a directory structure. The main branch (main) is selected at the top. Folders like .github, .reuse, LICENSES, and library are visible, with the library folder expanded to reveal files such as backtrace.rs, condvar.rs, fs.rs, and wtf8.rs, with wtf8.rs currently selected. The background features a gradient from green to teal."
              loading="lazy"
            />
          </River.Visual>

          <River.Content className="fp-River-content">
            <Text size="400" weight="semibold">
              <strong>File browser.</strong> Keep all your code in context and instantly switch files with the new file
              tree pane.
            </Text>
          </River.Content>
        </River>

        <Spacer size="64px" size1012="128px" />
      </div>
    </section>
  )
}
