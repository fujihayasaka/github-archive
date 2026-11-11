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
import {
  CreateAssessmentRequest,
  CreateAssessmentResponse,
  GetLatestAssessmentRequest,
  GetLatestAssessmentResponse,
  GetTokenTypeResultsRequest,
  GetTokenTypeResultsResponse,
  GetTokenTypeResultsCSVRequest,
  GetTokenTypeResultsCSVResponse,
  GetAssessmentRequest,
  GetAssessmentResponse,
  ListAssessmentsRequest,
  ListAssessmentsResponse,
  GetRepositoryResultsRequest,
  GetRepositoryResultsResponse,
} from "./assessments";

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

export interface AssessmentsAPIClient {
  CreateAssessment(
    request: CreateAssessmentRequest
  ): Promise<CreateAssessmentResponse>;
  GetLatestAssessment(
    request: GetLatestAssessmentRequest
  ): Promise<GetLatestAssessmentResponse>;
  GetTokenTypeResults(
    request: GetTokenTypeResultsRequest
  ): Promise<GetTokenTypeResultsResponse>;
  GetTokenTypeResultsCSV(
    request: GetTokenTypeResultsCSVRequest
  ): Promise<GetTokenTypeResultsCSVResponse>;
  GetAssessment(request: GetAssessmentRequest): Promise<GetAssessmentResponse>;
  ListAssessments(
    request: ListAssessmentsRequest
  ): Promise<ListAssessmentsResponse>;
  GetRepositoryResults(
    request: GetRepositoryResultsRequest
  ): Promise<GetRepositoryResultsResponse>;
}

export class AssessmentsAPIClientJSON implements AssessmentsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.CreateAssessment.bind(this);
    this.GetLatestAssessment.bind(this);
    this.GetTokenTypeResults.bind(this);
    this.GetTokenTypeResultsCSV.bind(this);
    this.GetAssessment.bind(this);
    this.ListAssessments.bind(this);
    this.GetRepositoryResults.bind(this);
  }
  CreateAssessment(
    request: CreateAssessmentRequest
  ): Promise<CreateAssessmentResponse> {
    const data = CreateAssessmentRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "CreateAssessment",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      CreateAssessmentResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetLatestAssessment(
    request: GetLatestAssessmentRequest
  ): Promise<GetLatestAssessmentResponse> {
    const data = GetLatestAssessmentRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "GetLatestAssessment",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetLatestAssessmentResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetTokenTypeResults(
    request: GetTokenTypeResultsRequest
  ): Promise<GetTokenTypeResultsResponse> {
    const data = GetTokenTypeResultsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "GetTokenTypeResults",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenTypeResultsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetTokenTypeResultsCSV(
    request: GetTokenTypeResultsCSVRequest
  ): Promise<GetTokenTypeResultsCSVResponse> {
    const data = GetTokenTypeResultsCSVRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "GetTokenTypeResultsCSV",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetTokenTypeResultsCSVResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetAssessment(request: GetAssessmentRequest): Promise<GetAssessmentResponse> {
    const data = GetAssessmentRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "GetAssessment",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetAssessmentResponse.fromJson(data as any, { ignoreUnknownFields: true })
    );
  }

  ListAssessments(
    request: ListAssessmentsRequest
  ): Promise<ListAssessmentsResponse> {
    const data = ListAssessmentsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "ListAssessments",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      ListAssessmentsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }

  GetRepositoryResults(
    request: GetRepositoryResultsRequest
  ): Promise<GetRepositoryResultsResponse> {
    const data = GetRepositoryResultsRequest.toJson(request, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    });
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "GetRepositoryResults",
      "application/json",
      data as object
    );
    return promise.then((data) =>
      GetRepositoryResultsResponse.fromJson(data as any, {
        ignoreUnknownFields: true,
      })
    );
  }
}

export class AssessmentsAPIClientProtobuf implements AssessmentsAPIClient {
  private readonly rpc: Rpc;
  constructor(rpc: Rpc) {
    this.rpc = rpc;
    this.CreateAssessment.bind(this);
    this.GetLatestAssessment.bind(this);
    this.GetTokenTypeResults.bind(this);
    this.GetTokenTypeResultsCSV.bind(this);
    this.GetAssessment.bind(this);
    this.ListAssessments.bind(this);
    this.GetRepositoryResults.bind(this);
  }
  CreateAssessment(
    request: CreateAssessmentRequest
  ): Promise<CreateAssessmentResponse> {
    const data = CreateAssessmentRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "CreateAssessment",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      CreateAssessmentResponse.fromBinary(data as Uint8Array)
    );
  }

  GetLatestAssessment(
    request: GetLatestAssessmentRequest
  ): Promise<GetLatestAssessmentResponse> {
    const data = GetLatestAssessmentRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "GetLatestAssessment",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetLatestAssessmentResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokenTypeResults(
    request: GetTokenTypeResultsRequest
  ): Promise<GetTokenTypeResultsResponse> {
    const data = GetTokenTypeResultsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "GetTokenTypeResults",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenTypeResultsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetTokenTypeResultsCSV(
    request: GetTokenTypeResultsCSVRequest
  ): Promise<GetTokenTypeResultsCSVResponse> {
    const data = GetTokenTypeResultsCSVRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "GetTokenTypeResultsCSV",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetTokenTypeResultsCSVResponse.fromBinary(data as Uint8Array)
    );
  }

  GetAssessment(request: GetAssessmentRequest): Promise<GetAssessmentResponse> {
    const data = GetAssessmentRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "GetAssessment",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetAssessmentResponse.fromBinary(data as Uint8Array)
    );
  }

  ListAssessments(
    request: ListAssessmentsRequest
  ): Promise<ListAssessmentsResponse> {
    const data = ListAssessmentsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "ListAssessments",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      ListAssessmentsResponse.fromBinary(data as Uint8Array)
    );
  }

  GetRepositoryResults(
    request: GetRepositoryResultsRequest
  ): Promise<GetRepositoryResultsResponse> {
    const data = GetRepositoryResultsRequest.toBinary(request);
    const promise = this.rpc.request(
      "github.secretscanning.v1.AssessmentsAPI",
      "GetRepositoryResults",
      "application/protobuf",
      data
    );
    return promise.then((data) =>
      GetRepositoryResultsResponse.fromBinary(data as Uint8Array)
    );
  }
}

//==================================//
//          Server Code             //
//==================================//

export interface AssessmentsAPITwirp<T extends TwirpContext = TwirpContext> {
  CreateAssessment(
    ctx: T,
    request: CreateAssessmentRequest
  ): Promise<CreateAssessmentResponse>;
  GetLatestAssessment(
    ctx: T,
    request: GetLatestAssessmentRequest
  ): Promise<GetLatestAssessmentResponse>;
  GetTokenTypeResults(
    ctx: T,
    request: GetTokenTypeResultsRequest
  ): Promise<GetTokenTypeResultsResponse>;
  GetTokenTypeResultsCSV(
    ctx: T,
    request: GetTokenTypeResultsCSVRequest
  ): Promise<GetTokenTypeResultsCSVResponse>;
  GetAssessment(
    ctx: T,
    request: GetAssessmentRequest
  ): Promise<GetAssessmentResponse>;
  ListAssessments(
    ctx: T,
    request: ListAssessmentsRequest
  ): Promise<ListAssessmentsResponse>;
  GetRepositoryResults(
    ctx: T,
    request: GetRepositoryResultsRequest
  ): Promise<GetRepositoryResultsResponse>;
}

export enum AssessmentsAPIMethod {
  CreateAssessment = "CreateAssessment",
  GetLatestAssessment = "GetLatestAssessment",
  GetTokenTypeResults = "GetTokenTypeResults",
  GetTokenTypeResultsCSV = "GetTokenTypeResultsCSV",
  GetAssessment = "GetAssessment",
  ListAssessments = "ListAssessments",
  GetRepositoryResults = "GetRepositoryResults",
}

export const AssessmentsAPIMethodList = [
  AssessmentsAPIMethod.CreateAssessment,
  AssessmentsAPIMethod.GetLatestAssessment,
  AssessmentsAPIMethod.GetTokenTypeResults,
  AssessmentsAPIMethod.GetTokenTypeResultsCSV,
  AssessmentsAPIMethod.GetAssessment,
  AssessmentsAPIMethod.ListAssessments,
  AssessmentsAPIMethod.GetRepositoryResults,
];

export function createAssessmentsAPIServer<
  T extends TwirpContext = TwirpContext
>(service: AssessmentsAPITwirp<T>) {
  return new TwirpServer<AssessmentsAPITwirp, T>({
    service,
    packageName: "github.secretscanning.v1",
    serviceName: "AssessmentsAPI",
    methodList: AssessmentsAPIMethodList,
    matchRoute: matchAssessmentsAPIRoute,
  });
}

function matchAssessmentsAPIRoute<T extends TwirpContext = TwirpContext>(
  method: string,
  events: RouterEvents<T>
) {
  switch (method) {
    case "CreateAssessment":
      return async (
        ctx: T,
        service: AssessmentsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          CreateAssessmentRequest,
          CreateAssessmentResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "CreateAssessment" };
        await events.onMatch(ctx);
        return handleAssessmentsAPICreateAssessmentRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetLatestAssessment":
      return async (
        ctx: T,
        service: AssessmentsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetLatestAssessmentRequest,
          GetLatestAssessmentResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetLatestAssessment" };
        await events.onMatch(ctx);
        return handleAssessmentsAPIGetLatestAssessmentRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokenTypeResults":
      return async (
        ctx: T,
        service: AssessmentsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenTypeResultsRequest,
          GetTokenTypeResultsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenTypeResults" };
        await events.onMatch(ctx);
        return handleAssessmentsAPIGetTokenTypeResultsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetTokenTypeResultsCSV":
      return async (
        ctx: T,
        service: AssessmentsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetTokenTypeResultsCSVRequest,
          GetTokenTypeResultsCSVResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetTokenTypeResultsCSV" };
        await events.onMatch(ctx);
        return handleAssessmentsAPIGetTokenTypeResultsCSVRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetAssessment":
      return async (
        ctx: T,
        service: AssessmentsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetAssessmentRequest,
          GetAssessmentResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetAssessment" };
        await events.onMatch(ctx);
        return handleAssessmentsAPIGetAssessmentRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "ListAssessments":
      return async (
        ctx: T,
        service: AssessmentsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          ListAssessmentsRequest,
          ListAssessmentsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "ListAssessments" };
        await events.onMatch(ctx);
        return handleAssessmentsAPIListAssessmentsRequest(
          ctx,
          service,
          data,
          interceptors
        );
      };
    case "GetRepositoryResults":
      return async (
        ctx: T,
        service: AssessmentsAPITwirp,
        data: Buffer,
        interceptors?: Interceptor<
          T,
          GetRepositoryResultsRequest,
          GetRepositoryResultsResponse
        >[]
      ) => {
        ctx = { ...ctx, methodName: "GetRepositoryResults" };
        await events.onMatch(ctx);
        return handleAssessmentsAPIGetRepositoryResultsRequest(
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

function handleAssessmentsAPICreateAssessmentRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CreateAssessmentRequest,
    CreateAssessmentResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleAssessmentsAPICreateAssessmentJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleAssessmentsAPICreateAssessmentProtobuf<T>(
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

function handleAssessmentsAPIGetLatestAssessmentRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetLatestAssessmentRequest,
    GetLatestAssessmentResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleAssessmentsAPIGetLatestAssessmentJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleAssessmentsAPIGetLatestAssessmentProtobuf<T>(
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

function handleAssessmentsAPIGetTokenTypeResultsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenTypeResultsRequest,
    GetTokenTypeResultsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleAssessmentsAPIGetTokenTypeResultsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleAssessmentsAPIGetTokenTypeResultsProtobuf<T>(
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

function handleAssessmentsAPIGetTokenTypeResultsCSVRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenTypeResultsCSVRequest,
    GetTokenTypeResultsCSVResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleAssessmentsAPIGetTokenTypeResultsCSVJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleAssessmentsAPIGetTokenTypeResultsCSVProtobuf<T>(
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

function handleAssessmentsAPIGetAssessmentRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetAssessmentRequest, GetAssessmentResponse>[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleAssessmentsAPIGetAssessmentJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleAssessmentsAPIGetAssessmentProtobuf<T>(
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

function handleAssessmentsAPIListAssessmentsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListAssessmentsRequest,
    ListAssessmentsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleAssessmentsAPIListAssessmentsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleAssessmentsAPIListAssessmentsProtobuf<T>(
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

function handleAssessmentsAPIGetRepositoryResultsRequest<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetRepositoryResultsRequest,
    GetRepositoryResultsResponse
  >[]
): Promise<string | Uint8Array> {
  switch (ctx.contentType) {
    case TwirpContentType.JSON:
      return handleAssessmentsAPIGetRepositoryResultsJSON<T>(
        ctx,
        service,
        data,
        interceptors
      );
    case TwirpContentType.Protobuf:
      return handleAssessmentsAPIGetRepositoryResultsProtobuf<T>(
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
async function handleAssessmentsAPICreateAssessmentJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CreateAssessmentRequest,
    CreateAssessmentResponse
  >[]
) {
  let request: CreateAssessmentRequest;
  let response: CreateAssessmentResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = CreateAssessmentRequest.fromJson(body, {
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
      CreateAssessmentRequest,
      CreateAssessmentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.CreateAssessment(ctx, inputReq);
    });
  } else {
    response = await service.CreateAssessment(ctx, request!);
  }

  return JSON.stringify(
    CreateAssessmentResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleAssessmentsAPIGetLatestAssessmentJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetLatestAssessmentRequest,
    GetLatestAssessmentResponse
  >[]
) {
  let request: GetLatestAssessmentRequest;
  let response: GetLatestAssessmentResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetLatestAssessmentRequest.fromJson(body, {
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
      GetLatestAssessmentRequest,
      GetLatestAssessmentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetLatestAssessment(ctx, inputReq);
    });
  } else {
    response = await service.GetLatestAssessment(ctx, request!);
  }

  return JSON.stringify(
    GetLatestAssessmentResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleAssessmentsAPIGetTokenTypeResultsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenTypeResultsRequest,
    GetTokenTypeResultsResponse
  >[]
) {
  let request: GetTokenTypeResultsRequest;
  let response: GetTokenTypeResultsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenTypeResultsRequest.fromJson(body, {
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
      GetTokenTypeResultsRequest,
      GetTokenTypeResultsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenTypeResults(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenTypeResults(ctx, request!);
  }

  return JSON.stringify(
    GetTokenTypeResultsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleAssessmentsAPIGetTokenTypeResultsCSVJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenTypeResultsCSVRequest,
    GetTokenTypeResultsCSVResponse
  >[]
) {
  let request: GetTokenTypeResultsCSVRequest;
  let response: GetTokenTypeResultsCSVResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetTokenTypeResultsCSVRequest.fromJson(body, {
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
      GetTokenTypeResultsCSVRequest,
      GetTokenTypeResultsCSVResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenTypeResultsCSV(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenTypeResultsCSV(ctx, request!);
  }

  return JSON.stringify(
    GetTokenTypeResultsCSVResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleAssessmentsAPIGetAssessmentJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetAssessmentRequest, GetAssessmentResponse>[]
) {
  let request: GetAssessmentRequest;
  let response: GetAssessmentResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetAssessmentRequest.fromJson(body, {
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
      GetAssessmentRequest,
      GetAssessmentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetAssessment(ctx, inputReq);
    });
  } else {
    response = await service.GetAssessment(ctx, request!);
  }

  return JSON.stringify(
    GetAssessmentResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleAssessmentsAPIListAssessmentsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListAssessmentsRequest,
    ListAssessmentsResponse
  >[]
) {
  let request: ListAssessmentsRequest;
  let response: ListAssessmentsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = ListAssessmentsRequest.fromJson(body, {
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
      ListAssessmentsRequest,
      ListAssessmentsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListAssessments(ctx, inputReq);
    });
  } else {
    response = await service.ListAssessments(ctx, request!);
  }

  return JSON.stringify(
    ListAssessmentsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}

async function handleAssessmentsAPIGetRepositoryResultsJSON<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetRepositoryResultsRequest,
    GetRepositoryResultsResponse
  >[]
) {
  let request: GetRepositoryResultsRequest;
  let response: GetRepositoryResultsResponse;

  try {
    const body = JSON.parse(data.toString() || "{}");
    request = GetRepositoryResultsRequest.fromJson(body, {
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
      GetRepositoryResultsRequest,
      GetRepositoryResultsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetRepositoryResults(ctx, inputReq);
    });
  } else {
    response = await service.GetRepositoryResults(ctx, request!);
  }

  return JSON.stringify(
    GetRepositoryResultsResponse.toJson(response, {
      useProtoFieldName: true,
      emitDefaultValues: false,
    }) as string
  );
}
async function handleAssessmentsAPICreateAssessmentProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    CreateAssessmentRequest,
    CreateAssessmentResponse
  >[]
) {
  let request: CreateAssessmentRequest;
  let response: CreateAssessmentResponse;

  try {
    request = CreateAssessmentRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      CreateAssessmentRequest,
      CreateAssessmentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.CreateAssessment(ctx, inputReq);
    });
  } else {
    response = await service.CreateAssessment(ctx, request!);
  }

  return Buffer.from(CreateAssessmentResponse.toBinary(response));
}

async function handleAssessmentsAPIGetLatestAssessmentProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetLatestAssessmentRequest,
    GetLatestAssessmentResponse
  >[]
) {
  let request: GetLatestAssessmentRequest;
  let response: GetLatestAssessmentResponse;

  try {
    request = GetLatestAssessmentRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetLatestAssessmentRequest,
      GetLatestAssessmentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetLatestAssessment(ctx, inputReq);
    });
  } else {
    response = await service.GetLatestAssessment(ctx, request!);
  }

  return Buffer.from(GetLatestAssessmentResponse.toBinary(response));
}

async function handleAssessmentsAPIGetTokenTypeResultsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenTypeResultsRequest,
    GetTokenTypeResultsResponse
  >[]
) {
  let request: GetTokenTypeResultsRequest;
  let response: GetTokenTypeResultsResponse;

  try {
    request = GetTokenTypeResultsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenTypeResultsRequest,
      GetTokenTypeResultsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenTypeResults(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenTypeResults(ctx, request!);
  }

  return Buffer.from(GetTokenTypeResultsResponse.toBinary(response));
}

async function handleAssessmentsAPIGetTokenTypeResultsCSVProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetTokenTypeResultsCSVRequest,
    GetTokenTypeResultsCSVResponse
  >[]
) {
  let request: GetTokenTypeResultsCSVRequest;
  let response: GetTokenTypeResultsCSVResponse;

  try {
    request = GetTokenTypeResultsCSVRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetTokenTypeResultsCSVRequest,
      GetTokenTypeResultsCSVResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetTokenTypeResultsCSV(ctx, inputReq);
    });
  } else {
    response = await service.GetTokenTypeResultsCSV(ctx, request!);
  }

  return Buffer.from(GetTokenTypeResultsCSVResponse.toBinary(response));
}

async function handleAssessmentsAPIGetAssessmentProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<T, GetAssessmentRequest, GetAssessmentResponse>[]
) {
  let request: GetAssessmentRequest;
  let response: GetAssessmentResponse;

  try {
    request = GetAssessmentRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetAssessmentRequest,
      GetAssessmentResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetAssessment(ctx, inputReq);
    });
  } else {
    response = await service.GetAssessment(ctx, request!);
  }

  return Buffer.from(GetAssessmentResponse.toBinary(response));
}

async function handleAssessmentsAPIListAssessmentsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    ListAssessmentsRequest,
    ListAssessmentsResponse
  >[]
) {
  let request: ListAssessmentsRequest;
  let response: ListAssessmentsResponse;

  try {
    request = ListAssessmentsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      ListAssessmentsRequest,
      ListAssessmentsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.ListAssessments(ctx, inputReq);
    });
  } else {
    response = await service.ListAssessments(ctx, request!);
  }

  return Buffer.from(ListAssessmentsResponse.toBinary(response));
}

async function handleAssessmentsAPIGetRepositoryResultsProtobuf<
  T extends TwirpContext = TwirpContext
>(
  ctx: T,
  service: AssessmentsAPITwirp,
  data: Buffer,
  interceptors?: Interceptor<
    T,
    GetRepositoryResultsRequest,
    GetRepositoryResultsResponse
  >[]
) {
  let request: GetRepositoryResultsRequest;
  let response: GetRepositoryResultsResponse;

  try {
    request = GetRepositoryResultsRequest.fromBinary(data);
  } catch (e) {
    if (e instanceof Error) {
      const msg = "the protobuf request could not be decoded";
      throw new TwirpError(TwirpErrorCode.Malformed, msg).withCause(e, true);
    }
  }

  if (interceptors && interceptors.length > 0) {
    const interceptor = chainInterceptors(...interceptors) as Interceptor<
      T,
      GetRepositoryResultsRequest,
      GetRepositoryResultsResponse
    >;
    response = await interceptor(ctx, request!, (ctx, inputReq) => {
      return service.GetRepositoryResults(ctx, inputReq);
    });
  } else {
    response = await service.GetRepositoryResults(ctx, request!);
  }

  return Buffer.from(GetRepositoryResultsResponse.toBinary(response));
}
