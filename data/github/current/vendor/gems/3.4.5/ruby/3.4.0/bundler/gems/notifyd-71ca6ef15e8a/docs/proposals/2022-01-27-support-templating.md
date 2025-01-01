# [Proposal] Support html templating in notifyd

## Brief

[Support html templating for emails being sent via notifyd](https://github.com/github/notifyd/pull/682)

## Overview

We have described in the [brief](https://github.com/github/notifyd/pull/682) that we want to support sending emails from notifyd using templates.

For that, we need to:
- Study whether the option of managing templates in notifyd it's a good idea or not.
- How easy could be adding/modifying templates in notifyd?

For the expected outcome, we want notifyd emails have a structure similar to this layout:

![image](https://user-images.githubusercontent.com/8514581/151193535-400e5bdb-b4e4-4f81-9be0-f5efeb3338f2.png)

This document is aiming to describe possible solutions to handle templates in notifyd and list tradeoffs.

## Considerations

Checking the [layout email code from the monolith](https://github.com/github/github/blob/master/app/views/mailers/layouts/primer_layout.html.erb) is created,
to build something similar in notifyd we will need to support:
- `header`, `body`, `footer_text` and `subject` are mandatory
- `content_header`, `content_footer` are optional

`footer_links`, assets and how to add Primer components are out of the scope of this proposal.

## Solution exploration

We have considered several options to solving this problem:

### Solution 1: Use notifyd to manage templates

In the first solution, we use notifyd to manage email templating.
With this approach emails we will need these components:

- **Build html templates in notifyd**

In the monolith, each integrator creates their own template using [`content_for`](https://github.com/github/github/blob/master/app/views/mailers/billing_notifications/bundled_license_assignment_created.html.erb#L1-L3) that Rails provides to render custom header, body or footer content, and
using the [`primer_layout.html.erb`](https://github.com/github/github/blob/master/app/views/mailers/layouts/primer_layout.html.erb) as a base.

It's possible to do the same in notifyd using [`template` library from go](https://pkg.go.dev/text/template).
This will allow integrators to create their own html templates. In [this example](https://github.com/jezcommits/go-templates/tree/main/templating-spike), we can check how it works: [`template.html`](https://github.com/jezcommits/go-templates/blob/main/templating-spike/template.html)
works here as a layout and [`partial1`](https://github.com/jezcommits/go-templates/blob/main/templating-spike/partial1.html) is the html content rendered inside the layout.

This is an spike of a possible solution for issues: https://github.com/github/notifyd/pull/691/files
The general idea is to have all the templates in one place and a principal `layout.html` that is the base:

![Screenshot 2022-01-28 at 12 57 55](https://user-images.githubusercontent.com/8514581/151543218-cd46231f-8b7f-4cd9-a7ac-8929418b4c4d.png)

The `layout.html` will render different parts of the email, depending on the subject:

```
<body>
  <div id="email-content">
    {{template "header" .}}

    <div id="email-body">
      {{template "body" .}}
    </div>

    {{template "footer" .}}
  </div>
</body>

```

And layout and templates will be retrieved from the `sender.go` to generate the message:
```
message, err := template.ParseFiles("layout/layout.html", "layout/templates/issues/header.html",...)

```

We will use this solution to print custom headers, body and footers in the layout. 

**Benefits:**

- Templating logic is decoupled from the monolith, that is one of our guiding principles.
- Email template management will be holded by notifyd. This will allow integrators to easily maintain and extend their own templates.
- It's easier to improve the look and feel of notifications emails.

**Drawbacks**

- We will have dependencies of the monolith pending to be solved in the following iterations, for example footer links.
- [mail-replies](https://github.com/github/mail-replies) will stop working for this solution. So we will need to fix/rebuild it and we don't know the time it will take.

### Solution 2: Use the monolith to manage templates

This is already being done. Integrators create their own [templates in mailers](https://github.com/github/github/tree/master/app/views/mailers). For example, [`bundled_license_assignment_created.html.erb`](https://github.com/github/github/blob/master/app/views/mailers/billing_notifications/bundled_license_assignment_created.html.erb) uses primer layout defined [in the mailer](https://github.com/github/github/blob/master/app/mailers/billing_notifications_mailer.rb#L6).

The only need here is that we need to provide this layout and integrator's template to notifyd sender somehow. So there are two options:
1. Provide html in [`email_layout`](https://github.com/github/github/blob/master/app/models/notifyd/issue_adapter.rb#L43-L48) message in the adapter. 
2. Request the html content and styles to the monolith.

These solutions introduce complexity: we will need to adjust the max size of a hydro message or split the message in smaller ones.
Also, we are trying to [minimise making requests to the monolith](https://github.com/github/notifyd/blob/main/docs/adr/0003-minimise-requests-from-the-notifications-service-back-to-the-monolith.md).

**Benefits:**

- Primer email layout is already in the monolith ready to be used by integrators.
- Some events like github links are easy to add.
- It will improve the look and feel of notifications emails.

**Drawbacks**

- We heavily depend on the monolith. Templates won't be easy to maintain.
- It goes against our intentions to isolate notifyd logic from the monolith.
- Some events are difficult to add like unsubscribing, as it depends now on notifyd.
- Some actions will be [temporarily broken](https://github.com/github/notifyd/pull/682#discussion_r793358138) like [mail-replies](https://github.com/github/mail-replies).
- We need to get the html layout and template in notifyd from the monolith. That is a dependency that introduces complexity, as described above.
- It is an expensive operation: either sending the whole html template and styles via requests or via hydro messages that has a size limit of 5MB, is costly.

## Proposed solution

We think our preferred solution is **option 1: Use notifyd to manage templates**.

**Reasoning**: This solution will provide us more benefits than drawbacks in the long term for us to manage templates and for integrators.
Also option 2 is something we are trying to avoid by creating notifyd service: we want to rely as little as possible on the monolith.
