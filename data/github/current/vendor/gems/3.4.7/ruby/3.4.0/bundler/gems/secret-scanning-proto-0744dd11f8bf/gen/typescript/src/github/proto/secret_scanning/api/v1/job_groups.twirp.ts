import {
  TwirpContext,
  TwirpServer,
  RouterEvents,
  TwirpError,
  TwirpErrorCode,
  Interceptor,
  TwirpContentType,
  chainInterceptors,
} from "twirp-ts";
import { JobGroupSummaryRequest, JobGroupSummaryResponse } from "./job_groups";

//==================================//
//          Client Code             //
//==================================//

interface Rpc {
  request(
    service: string,
    method: string,
    contentType: "application/json" | "application/protobuf",
    data: object | Uint8Array
  ): Promise<object | Uint8Array>;
}

export interface JobGroupsAPIClient {
  GetJobGroupSummary(
    request: JobGroupSummaryRequest
  ): Promise<JobGroupSummaryResponse>;
}

export class JobGroupsAPIClientJSON implements JobGroupsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetJobGroupSummary.bind(this);
  }
  GetJobGroupSummary(
    request: JobGroupSummaryRequest
  ): Promise<JobGroupSummaryResponse> {
    const data = JobGroupSummaryRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.JobGroupsAPI",
      "GetJobGroupSummary",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      JobGroupSummaryResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class JobGroupsAPIClientProtobuf implements JobGroupsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.GetJobGroupSummary.bind(this);
  }
  GetJobGroupSummary(
    request: JobGroupSummaryRequest
  ): Promise<JobGroupSummaryResponse> {
    const data = JobGroupSummaryRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.JobGroupsAPI",
      "GetJobGroupSummary",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      JobGroupSummaryResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface JobGroupsAPITwirp<T extends TwirpContext = TwirpContext> {
  GetJobGroupSummary(
    ctx: T,
    request: JobGroupSummaryRequest
  ): Promise<JobGroupSummaryResponse>;
}

export enum JobGroupsAPIMethod {
  GetJobGroupSummary = "GetJobGroupSummary",
}

export const JobGroupsAPIMethodList = [JobGroupsAPIMethod.GetJobGroupSummary];

export function createJobGroupsAPIServer<T extends TwirpContext = TwirpContext>(
  service: JobGroupsAPITwirp<T>
) {
  return new TwirpServer<JobGroupsAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "JobGroupsAPI",
    methodList: JobGroupsAPIMethodList,
    matchRoute: matchJobGroupsAPIRoute,
  });
}

function matchJobGroupsAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "GetJobGroupSummary":
      return async (
        ctx: T,
        service: JobGroupsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          JobGroupSummaryRequest,
          JobGroupSummaryResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetJobGroupSummary" };
        await events.onMatch(ctx);
        return handleJobGroupsAPIGetJobGroupSummaryRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    default:
      events.onNotFound();
      const msg = `no handler found`;
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}

function handleJobGroupsAPIGetJobGroupSummaryRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: JobGroupsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    JobGroupSummaryRequest,
    JobGroupSummaryResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleJobGroupsAPIGetJobGroupSummaryJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleJobGroupsAPIGetJobGroupSummaryProtobuf<T>(
        ctx,
        service,
        data,
        interceptors
      );
    default:
      const msg = "unexpected Content-Type";
      throw new TwirpError(TwirpErrorCode.BadRoute, msg);
  }
}
async function handleJobGroupsAPIGetJobGroupSummaryJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: JobGroupsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    JobGroupSummaryRequest,
    JobGroupSummaryResponse
  >[]
) {
  let request: JobGroupSummaryRequest;
  let response: JobGroupSummaryResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = JobGroupSummaryRequest.fromJson(body, {
      ignoreUnknownFields: true,
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the json request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      JobGroupSummaryRequest,
      JobGroupSummaryResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetJobGroupSummary(ctx, inputReq);
    });
  } else {
    response = await service.GetJobGroupSummary(ctx, request!);
  }

  return JSON.stringify(
    JobGroupSummaryResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleJobGroupsAPIGetJobGroupSummaryProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: JobGroupsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    JobGroupSummaryRequest,
    JobGroupSummaryResponse
  >[]
) {
  let request: JobGroupSummaryRequest;
  let response: JobGroupSummaryResponse;

  try {
    request = JobGroupSummaryRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      JobGroupSummaryRequest,
      JobGroupSummaryResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetJobGroupSummary(ctx, inputReq);
    });
  } else {
    response = await service.GetJobGroupSummary(ctx, request!);
  }

  return Buffer.from(JobGroupSummaryResponse.toBinary(response));
}
