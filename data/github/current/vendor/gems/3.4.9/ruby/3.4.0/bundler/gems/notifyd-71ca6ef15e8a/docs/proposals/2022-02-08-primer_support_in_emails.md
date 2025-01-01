# [Proposal] Support Primer styling for Notifyd emails

## Brief

[Support html templating for emails being sent via notifyd](https://github.com/github/notifyd/pull/682)

## Overview

We have described in the [brief](https://github.com/github/notifyd/pull/682) that we want to support sending emails from notifyd using templates styled using CSS libraries, 
for example Primer library.

For that, we need to:
- Pave the path to style emails that is easy for integrators.
- Find the way to reuse existign design systems defined in Primer library

For the expected outcome, we want notifyd emails to be styled with Primer css library:

![image](https://user-images.githubusercontent.com/8514581/151193535-400e5bdb-b4e4-4f81-9be0-f5efeb3338f2.png)

This document is aiming to describe possible solutions to use styling in emails and discuss possible tradeoffs.

## Considerations

### Emails are managed in Notifyd

Per previous proposal and some PRs we have implemented in Notifyd, email templates will be managed inside of Notifyd codebase.
Links to existing templating folder:

### Premail library 

Checking [code in the monolith](https://github.com/github/github/blob/bd7520da7b7e3aead75005c7084c6d9b301a8807/app/mailers/newsies_mailer.rb#L72) that takes care of transforming primer templates to final HTML markup that will be sent to the user we can see that we already 
[use Premail library](https://github.com/premailer/premailer). 

It takes care of inlining CSS rules defined in classes into `style="..."` tags and is executed in dotcom's runtime. Inlining styles is well known way to support CSS styling in emails.

## Solution exploration

We have considered several options to solving this problem:

### Solution 1: Put entire Primer library into styles tag on email HTML body

As possible solution we could put entire Primer library css into `<styles>` tag and use `class` attributes directly. 

Consider this diagram:

![image](https://user-images.githubusercontent.com/5173831/153011878-e02d3e56-f399-4b72-a80f-0f2449b899eb.png)

We could come up with the process to include contents of `primer.css` to a `<style>` tag that will be injected to email body. The rest of the email body content will be able to use primer related CSS.

**Benefits:**

- It will be possible to use primer classes directly that our integrators should be familiar with.
- This step doesn't require any pre-processing steps
- 
**Drawbacks**
- Including entire primer library is *relatively* big (483Kb) and will *moderately* increase final email size
- Lots of included styles will be unused

### Solution 2: Use Premailer library to generate html templates with inlined styles

Idea here is to generate style-inlined version of tempaltes separately from Golang runtime using external libraries, like Ruby Premailer gem that is used on dotcom.

During the runtime we Notifyd application should not care if styles are inlined or not - it's important for end client application that will display email contents. That's why we could create a script `./script/pre-inline-styles-emails.sh` that will make use of any good open source library to inline styles for our templates.

Consider following flow:
![image](https://user-images.githubusercontent.com/5173831/153016599-a7b82c77-3d17-4ab0-bfc5-7e0fd739540a.png)

1. Integrator should create templates that will use Primaer.css classes directly kind of a Dev version of templates, for example `views/templates/issue/body.html` or `views/templates/issue/footer.html`
2. Integrator or automated GitHub action will run automatically and generate `views/templates/issue/footer.gen.html` or `views/templates/issue/body.gen.html` 
`body.gen.html` version would contain markup version with class attributes `class="m-1 color-bg p-2"` primer css class rules to style attributes `style="margin: 1px; background-color: #123456; padding: 1px"`. Such `*.gen.html` files would be commited to the codebase.
3. Notifyd will use generated `*.gen.html` version with zero runtime risk. 

It's possible to transform Go tempaltes partials - libraries like **Premailer** seem to ignore Go syntax well, but we will need to spike into it to prove that Premailer works well with:
- includes
- loops
- conditions

**Benefits:**

- No extra processing costs on sending emails step
- Integratros can stil use Primer classes
- We are not wired to specific tool to do HTML inlining

**Drawbacks**

- We will need to create process of generating html templates with inlined HTML
- There is risk that original and generated files will be our of sync. 
- Style inlining tools will have problems with conditional CSS rules with Go tempating code in clases

### Solution 3: Create microservie responsible for notification templates

Another solution that we can consider is creating separate service that will be responsible for managing and transforming templates.

Consider this diagram: 
![image](https://user-images.githubusercontent.com/5173831/153448413-b51146a4-0f73-4066-94e6-8e567ab6624a.png)

As possible alternative we can introduce `templates-service` that will:
1. At the first iteration transform templates from `class=""` version to inlined `style=""` CSS version. 

At first Notifyd will still manage templates but will use `templates-service` written in Ruby for example to transform templates into proper form.

2. In near future `templates-service` could take ownership of integrator templates and even provide possiblity for integrators to edit/preview templates.   
See concept diagram below:

![image](https://user-images.githubusercontent.com/5173831/153450156-badf0974-be46-4b35-88d9-3a11e36bfa1c.png)

### Solution 4: Post process templates on dotcom using Premailer

In this solution we still want to introduce a microservice to post process email content outside of the Golang context. 
However we don't want to handle overhead of setting up new service, scaling it setting up new twirp api and auth. It seemed like overkill for setting up single state-less endpoint. 

Consider this diagram:
![image](https://user-images.githubusercontent.com/5173831/154960078-d3542778-9c7c-44ba-9946-d75379bb34c0.png)

As an alternative we can use private dotcom twirp API and do email body post processing in context of dotcom.

In case if external API call fails, for **Solution 3** and **Solution 4**  we need also to think about fallback option. 
For this case we have decided to send plain html body for now. 

![image](https://user-images.githubusercontent.com/5173831/154960180-98d4bcf1-12c8-4378-9b3d-46f72548c785.png)


Another argument for using Dotcom as templating service is the fact that Actions team uses custom compiled Primer CSS library build `primer-email`. 
It uses inlined colors instead of CSS variables which are easier to be inlined into email content. 

**Benefits:**

- We wil reuse exact library for email pre-processing as we do now in newsies
- In docom it's easy to get access to `primer-email` build of Primer library that uses inlined colors instead of CSS variables.
- Dotcom is already upscaled so we don't need to worry about handling extra microservice in order to support single endpoint.

**Drawbacks**

- Making API call means that we need to take care of possibe errors communicating with this service. 
- Higher upfront investment from effort side

## Proposed solution

We think our preferred solution is **option 4: Post process templates on dotcom using Premailer

**Reasoning**: 
It's clear that we will need _some kind of templating service_ in the future, however setting up microservice that would handle single action seemed to us as an overkill. We want to build templating service when we can collect more requirements and use-cases for it. 
