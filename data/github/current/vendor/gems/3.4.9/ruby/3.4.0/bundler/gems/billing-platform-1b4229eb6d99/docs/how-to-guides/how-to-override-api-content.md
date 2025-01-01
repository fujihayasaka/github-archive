# How to Override API content

You can use Chrome Devtools to make an override for API responses, which can be super useful for the various places that we are using Kusto in a codespace (which doesn't work in a codespace!).

## How to do it

1. Go to production and copy an API response from the `Network` tab of your Chrome devtools
2. In the network tab of your codespace or local development, right-click on the API method and select `Override content`
![Network tab with right-click open](https://github.com/user-attachments/assets/1caccaa2-9500-4972-841d-8f4a4f7c9a8b)
3. Paste in the content that you want instead!
![Overridden content in the Sources tab](https://github.com/user-attachments/assets/fd8392d1-8517-4458-a887-f7581d0a4209)
4. Now refresh the page. The API response that you pasted should be the one that shows up!

- This method matches on the URL name. If the URL changes (for example, if you select a different grouping or search option in the usage chart), you won't see that same overridden content.



