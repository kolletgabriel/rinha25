# Instructions for the Challenge

This document serves as a guide for you to implement your own solution to the challenge. The [original instructions](https://github.com/zanfranceschi/rinha-de-backend-2025/blob/main/INSTRUCOES.md) are in portuguese.

Instructions on how to simply run the implementation in this repository instead are found on the `README.md` file in the root directory. ***GLHF!***

## An Overview

This challenge consists in creating a RESTful service for handling payment requests by registering them and forwarding to *actual* payment service providers (PSPs) responsible to process them. You might think of it as a microservice from an ecommerce platform talking to a 3rd party payment gateway like Stripe.

The **goal** is essentially to make the most possible amount of money out of the payments, but the **problem** is that your service must talk with 2 different PSPs that charge different fees:

- one default, charging 7% per payment;
- one fallback, for when the 1st is unavailable, charging 10%.

It is a possibility, however, that both go unavailable at the same time!

Previous editions used Gatling as the load testing tool, but this one uses **Grafana K6** instead. The simulation will validate your implementation and test its *steadiness* under pressure.

## Basic Instructions

You need to build a web service that:

- provides 2 endpoints itself;
- calls 2 endpoints provided by the PSPs.

The specifications for the ones you must implement and the ones provided by the PSPs are described in the next section.

**In short:** besides accepting payment requests and forwarding them while managing eventual downtime of the PSPs by hitting their *healthcheck* endpoint, your service also needs to keep record of the successful payments in order to be able to compute summaries when requested.

### Scoring

Your score for this challenge is equal to the **total net revenue** collected from all the succsessful payments handled by your service. The net revenue is the sum of each payment after applying the PSP's fee (which, as previously stated, differs between both services).

You **earn bonuses** for fast response times and **pay penalties** for inconsistencies found on the summary. The total amount/score you've made after the test ends is calculated by:

```
total = net_revenue + (net_revenue*bonuses) - (net_revenue*penalties)
```

The bonuses for low latency are based on the P99 shown on the K6 report, available after the simulation ends. The value is calculated by the formula `max( (11-P99)*0.02 , 0 )`. That means, for instance, a P99 of 9ms would grant a bonus of 4% over the net revenue.

An inconsistency is any difference between the summary given by your service and the one given by the PSPs. The penalty is of **35%** over the net revenue, and that same value applies for any number of inconsistencies greater than 0.

## Endpoints

This section documents the endpoints you have to implement yourself, as well as the ones provided by the PSPs that your service just need to call.

### To Implement

As mentioned, your service only needs 2 endpoints. The requirements are described below.

#### `POST /payments`

This is your application's **main** endpoint. It simply accepts payment requests containing an ID and an amount. See the example below:

```json
{
   "correlationId":"4a7901b8-7d26-4d9d-aa19-4dc1c7cf60b3",
   "amount": 19.90
}
```

The field `correlationId` is an UUID, while `amount` is a decimal number. Both are mandatory.

> [!TIP]
> K6 will send the same `"amount": 19.90` during the entire test.

The response can be anything in the `2XX` range with no need for a body. The test won't send malformed requests of any kind, so no `4XX` nor `5XX` responses are required to be implemented.

#### `GET /payments-summary?from=<timestamp>&to=<timestamp>`

This endpoint computes the sum of the total number of requests and the total amount in U$ sent to both **default** and **fallback** PSPs. Query parameters `from` and `to` are timestamps in **RFC 3339** format with UTC time.

The response is always `200 OK` with a body like the example below:

```json
{
   "default" : {
     "totalRequests": 43236,
     "totalAmount": 415542345.98
   },
   "fallback" : {
     "totalRequests": 423545,
     "totalAmount": 329347.34
   }
}
```

The fields `totalRequests` and `totalAmount` are of the type integer and decimal, respectively.

### To Call

Of all the available endpoints from the PSPs' API, your service needs to integrate only with 2. The other ones are documented in the `README.md` under the `psp/` directory.

#### `POST /payments`

This is the endpoint for your API to forward payment requests to. Its body is the same as the one you must implement, with only 1 more field `requestedAt` for an RFC 3339 timestamp with UTC time.

```json
{
   "correlationId": "4a7901b8-7d26-4d9d-aa19-4dc1c7cf60b3",
   "amount": 19.9,
   "requestedAt": "2025-07-15T12:34:56.000Z"
}
```

The response for a successful transaction is `200 OK` with the following body:

```json
{
   "message": "payment processed successfully"
}
```

The PSP always checks for the `correlationId` on its database. If you're sending the same payment twice (after a successfull attempt, of course), the PSP will respond with `422 UNPROCESSABLE ENTITY`.

During eventual instability, however, this endpoint will return a `500 INTERNAL SERVER ERROR` response.

#### `GET /payments/service-health`

You can call this endpoint to verify the availability and responsiveness of a particular PSP. Example below for a `200 OK` response:

```json
{
   "failing": false,
   "minResponseTime": 100
}
```

The `failing` field is a boolean that indicates if `POST /payments` requests will succeed or not. If `true`, requests to `POST /payments` are getting `5XX` responses. `minResponseTime` holds the **minimum** latency in miliseconds as an integer value.

The catch is that **this endpoint can only be called once in 5 seconds!** If more than 1 request is made during a 5s interval, a `429 TOO MANY REQUESTS` response will be sent.

## Constraints and Architecture

Everything will run under Docker Compose. The architecture must consist **at least** of:

- a load balancer listening on `localhost:9999`;
- a minimum of 2 instances of the implemented web service.

You *should* add a 3rd component for storage. The **resource usage** for all declared components must not exceed **1.5 CPUs and 350MB of RAM**.

>[!NOTE]
> This **does not** include the PSPs. They have their own `compose.yml` file.

Finally: the network mode must be `bridge` (the default), and **no service** is allowed to run with `privileged: true`.

### Integrating with the PSPs

To integrate your service with the PSPs, you need to declare the `payment-processor` network in the `services.your_backend.networks` list and declare this network as `external: true` in the `networks` top-level element of the Compose file. For everything to work, the PSPs need to be up and running **before** your service starts.

Your service can talk to the default and fallback PSPs by calling `http://payment-processor-default:8080` and `http://payment-processor-fallback:8080` respectively. They're also available at `http://localhost:8001` and `http://localhost:8002` for quick testing.
