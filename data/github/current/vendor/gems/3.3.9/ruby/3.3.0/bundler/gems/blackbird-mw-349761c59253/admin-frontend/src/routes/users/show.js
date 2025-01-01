import { CheckIcon } from "@primer/octicons-react";
import {
  Link,
  Box,
  Heading,
  PageLayout,
  Button,
  Text,
  Octicon,
  Pagehead,
} from "@primer/react";
import { useLoaderData, useParams } from "react-router";
import { useFetcher } from "react-router-dom";
import { getUser, resetUserQuota } from "../../api";
import { getSplunkLink } from "../../components/splunk";
import { getStafftoolsLink } from "../../components/stafftools";

export async function loader({ params }) {
  return getUser(params.stamp, params.login);
}

export async function action({ request, params }) {
  return resetUserQuota(params.stamp, params.login);
}

export default function User() {
  const user = useLoaderData();
  const fetcher = useFetcher();
  const params = useParams();

  const didReset = !!fetcher.data;

  return (
    <PageLayout>
      <PageLayout.Content>
        <Pagehead>
          <Heading as="h2" sx={{ fontSize: 3 }}>
            <Link href={getStafftoolsLink(params.stamp, `users/${params.login}`)}>
              {params.login}
            </Link>
          </Heading>
        </Pagehead>

        <Box sx={{mb: 3}}>
          <Text color="fg.subtle" ontSize={1}>
            <Text sx={{ mr: 1 }}>Splunk:</Text>
            <Link
              href={getSplunkLink(
                "blackbird-ingest",
                "",
                params.login,
                params.stamp
              )}
            >
              ingest
            </Link>
            <Text sx={{ mx: 1 }}>·</Text>
            <Link
              href={getSplunkLink(
                "blackbird-query",
                "",
                params.login,
                params.stamp
              )}
            >
              query
            </Link>
          </Text>
        </Box>

        <Text fontWeight="bold" display="block">
          Rate limits
        </Text>
        <Box>
          <Text color="fg.subtle" fontSize={1} display="block" sx={{ mb: 2 }}>
            Manage rate limit quotas for this user.
          </Text>
          <fetcher.Form method="post">
            <Box display="flex" alignItems="center">
              <Button type="submit" variant="danger">
                Reset quotas
              </Button>
              {didReset && (
                <Text fontSize={1} color="success.fg" sx={{ ml: 2 }}>
                  <Octicon icon={CheckIcon} /> Success! Quotas reset.
                </Text>
              )}
            </Box>
          </fetcher.Form>
        </Box>

        <Pagehead>Raw JSON</Pagehead>
        <Box>
          <pre>{JSON.stringify(user, null, 2)}</pre>
        </Box>
      </PageLayout.Content>
    </PageLayout>
  );
}
