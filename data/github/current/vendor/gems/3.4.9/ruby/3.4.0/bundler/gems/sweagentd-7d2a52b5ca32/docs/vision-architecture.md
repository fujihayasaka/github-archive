# Vision Support for Copilot Coding Agent

In order to allow for additional user flows around image understanding, there is support for vision in the Copilot Coding Agent. This allows for the agent to use images committed to the repo, uploaded by users and generated through tools such as Playwright MCP to provide additional context to the session.

The image is sent to the model as a remote url in MultiContent message:

```
 {
    "role": "user",
    "content": [
      {
        "type": "text",
        "text": "Here is the image url: https://github.com/user-attachments/assets/9300859f-46c9-4d16-80b0-c9fd0f38adb3"
      },
      {
        "type": "image_url",
        "image_url": {
          "url": "https://github.com/user-attachments/assets/9300859f-46c9-4d16-80b0-c9fd0f38adb3"
        }
      }
    ]
 }
```


There are three distinct flows with images we support:

1. Image tags which includes `<img src=url>` and markdown tags like `![image](url)` in the problem statement body. Su
2. Image tags inside README files and docs in the repo (committed images). Image url can be relative `![image](./architecture.png)` or absolute `![image](https://github.com/github/sweagentd/blob/main/docs/architecture.png)`
3. Images returned from MCP like playwright in form of base64-encoded binary content. In this case image is uploaded as user attachment and sent as image url.

We always send images as remote urls and we never send base64-encoded images because of request size limits on CAPI's side.


## Committed Images Flow

Images can be recognised by HTML or Markdown tag in either Issue descriptions or files within the repository. This flow ensures that the images are visible to the agent regardless of whether they are referenced by absolute path or relative path.

Images are sent to CAPI in order to retrieve a signed URL for the image, which is then used to process the image for use in the agent.

### Sequence Diagram

```mermaid
sequenceDiagram
    Monolith->>sweagentd: issue description/file
    sweagentd->>Blackbird MCP: get repository insights
    Blackbird MCP->>sweagentd: repository insights
    Runtime->>Runtime: extract image urls from repo insights 
    Runtime->>Runtime: convert relative urls to absolute urls
    Runtime->>GitHub MCP: send request for image binary data
    GitHub MCP->>Runtime: receive image binary data as MCP resource
    Runtime->>Runtime: check image meets dimension & size requirements
    alt size and dimensions within the limit
    Runtime->>Copilot API: messages with image urls
        Copilot API->>Monolith: image urls 
        Monolith->>+Monolith: convert user attachment image urls to signed object storage urls 
        Monolith->>+Copilot API: signed urls
        alt model endpoint is GCP or AWS Bedrock
            Copilot API->>+Copilot API: download images and base64 encode
            Copilot API->>+Model Endpoint: images as base64
        else
            Copilot API->>+Model Endpoint: images as remote urls
        end
        Model Endpoint->>Copilot API: model response
        Copilot API->>Runtime: model response
    else
        Runtime->>Runtime: skip image
    end
```

*Depending on the model chosen by CAPI, the images will either be downloaded and sent as base64 or sent as remote URLs

## User Attachments Flow

This allows users to upload images via the GitHub UI, which are then processed by the sweagentd Runtime.
We support urls like `https://github.com/user-attachments/assets/<guid>` or legacy urls like `https://github.com/owner/repo/assets/user_id/<guid>`


```mermaid
sequenceDiagram
    User->>Monolith: upload image via GitHub UI and include image tag in issue description
    Monolith->>Monolith: store image as a user attachment
    Sweagent->>Runtime: problem statement (issue description) with image tags
    Runtime->>Runtime: extract image urls from problem statement
    Runtime->>Monolith: get signed urls for user attachments
    Monolith->>Runtime: signed object storage urls
    Runtime->>Object storage: download image
    Runtime->>Runtime: size/dimension check
    alt size and dimensions within the limit
    Runtime->>Copilot API: messages with attachment urls
        Copilot API->>Monolith: attachcment urls 
        Monolith->>+Monolith: convert user attachment image urls to signed object storage urls 
        Monolith->>+Copilot API: signed urls
        alt model endpoint is GCP or AWS Bedrock
            Copilot API->>+Copilot API: download images and base64 encode
            Copilot API->>+Model Endpoint: images as base64
        else
            Copilot API->>+Model Endpoint: images as remote urls
        end
        Model Endpoint->>Copilot API: model response
        Copilot API->>Runtime: model response
    else
        Runtime->>Runtime: skip image
    end
```


## Playwright MCP Screenshots Flow

The Playwright MCP is used to take screenshots if required by problem statement - for example, it is asked to make UI changes.

**IMPORTANT**: All the screenshots are uploaded as user attachments and sent to CAPI as urls, not base64.


```mermaid
sequenceDiagram
    Sweagentd->>Runtime: problem statement
    Runtime->>Playwright MCP: browser_take_screenshot tool call
    Playwright MCP->>Browser: launch/navigate to page
    Browser->>Playwright MCP: page ready
    Playwright MCP->>Playwright MCP: capture screenshot
    Playwright MCP->>Runtime: base64-encoded screenshot
    Runtime->>Runtime: check image meets dims & size requirements
    alt size and dimensions within the limit
        Runtime->>Alambic: upload image as user-attachment
        Alambic->>Runtime: user attachment url
        Runtime->>Copilot API: messages with image urls
        Copilot API->>Monolith: image urls 
        Monolith->>+Monolith: convert user attachment image urls to signed object storage urls 
        Monolith->>+Copilot API: signed urls
        alt model endpoint is GCP or AWS Bedrock
            Copilot API->>+Copilot API: download images and base64 encode
            Copilot API->>+Model Endpoint: images as base64
        else
            Copilot API->>+Model Endpoint: images as remote urls
        end
        Model Endpoint->>Copilot API: model response
        Copilot API->>Runtime: model response
    else
        Runtime->>Runtime: skip image
    end
```