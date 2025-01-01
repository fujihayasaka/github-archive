# Email template testing in notifyd

## Problem statement
The current implementation of full email template rendering consists on a high level of a 2 step process:

1. Generate the basic HTML template via Golang's `html/template`
2. Send the basic HTML template to a monolith twirp render endpoint to inline primer styles

Within this setup we have these current failure scenarios:
1. Basic HTML render fails completely
2. Basic HTML render results in broken template
3. CSS Inline fails completely
4. CSS Inline builds broken template

Arguably a complete failure is less bad than a seeming success that results in a broken template.

**Dev workflow challenges**
1. Unit testing of template changes
2. Iterating on template changes
3. (changes to the CSS inline service)

## Proposals
#### 1. Refactoring of template rendering to make it easier to unit test
This is mostly here for completeness since currently this logic is contained in the email `Send` function, but a refactoring to [change this is in flight](https://github.com/github/notifyd/pull/839) that will solve this problem for us.
#### 2. A tool to quickly generate a rendered template for inspection
This is mostly for iterating on a template and be able to quickly spot check a rendered notification before writing full blown unit test. This _could_ take the form of a cli tool that takes a notification in yaml format and renders a template with it:
```shell
% go run ./tools/render-template.go --notification notification.yaml --template primer.tpl
Template written to primer-12345.html
%
```
This would take time out of trying out changes to a template and we could look at the generated file in a browser to get a rough idea of what it looks like.

#### 3. Visual (diff) of email templates
There are a handful of visual diff tools for web pages. The most prominent most likely being  [Puppeteer](https://pptr.dev). With this we could generate a screenshot of the HTML (either in the dev workflow or in the PR) to visually spot check that it looks fine.
We could also have an option to take a screenshot of the template in current `main` and on the current ref and show them side by as a comparison (again ad hoc while developing or e.g. in a PR comment on push).
This could give some immediate feedback with the drawback that it's only going to show us HTML from a browser and not take into the account the edge cases that email client rendering brings with it.

**Testing as a service**
There are also a handful of services that provide testing facilities for visual email changes, e.g.:
- https://www.litmus.com/blog/how-to-streamline-your-email-testing-process-with-litmus/
- https://www.emailonacid.com/email-testing/
- https://ethereal.email/faq (this one is free and mostly provides a browser interface to the email)

These aren't necessarily cheap but would provide an avenue to get testing done on a variety of email clients. We'd have to go through procurement and see if we are able to spend that money, but could have a PR integration where we send a test email to the service and comment on the PR with a link to test it.

#### 4. Template versioning/feature flagging
In order to have a facility to safely roll out changes to templates after the dev workflow checks we have to big approaches we can do. Both rely on the premise that we want to decouple the code changes from the release to users in a way.

**Common requirements**

Either way we go here we need a way to distinguish between the test and control group so to speak. As in have a mechanism to roll out the new changes to say just us team members internally while the rest of our users see the old way still. And then flip it once we are confident that we've seen enough emails with the new layout to make it generally available.
This can be implemented in 2 phases, where we start with a static definition of email addresses that belong to the team, something along the lines of:
```go
if recipientGetsNewVersion(emailAddress) {...}
else {...} 
```
And if we see the need we could develop this further to tie into the dotcom feature flagging system and maybe even do percentage rollouts and A/B testing via scientist.
 
**Template versioning**

If we want to keep the templates themselves rather clean we can introduce template versioning so that we would never actually change a template but introduce a new version (e.g. `primer-v2`) that will be used. That way we don't have to deal too much with bloat in templates with the downside that we have to manage multiple template files and clean them up once they aren't used anymore. But we'd get "immutable templates" in a way that might be easier to reason about. In order to make it easier to debug we'd likely would want to embed the version as a comment in the HTML so we can track back from the email which template was used.

**Feature flagging in templates**

Another appraoch would be to do feature flagging in templates via the golang `html/template` primitives. This would mean more clauses of the form `{{if .ShowNewLink}}` and some bloat to the datastructure being passed into the render. And cleanup also becomes another code change that needs to be tested more, rather than a simple deletion of files that aren't referenced anymore. But on the upside there is only ever one template to look at to figure out what is being rendered.

## Caveats
In addition to the time some of that might take to implement, there is also an additional important point here which is the fact that CSS inlining processing is currently a monolith twirp endpoint and less accessible from dev systems and PRs than in production. That means for the visual part of verification for changes we'd likely have to implement a testing server or stub method that shells out to the ruby gem in test and dev which will mean additional surface area for potential deviations of the dev workflow from production. But is likely an ok trade-off to take in order to have any visual rendering at all.

## Summary
In order to successfully and easily change templates we want to gain confidence on multiple levels (in increasing complexity and feedback loop time):
- unit testing a change to a template
- visual testing of the rendered template
- validation of emails going through the whole flow
I think with the proposals outlined we'd have a decent set of tools to help with every stage of rolling out a change.
