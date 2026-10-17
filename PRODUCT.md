# deskView()

<!-- impeccable:product-schema 1 -->

## Platform

Native macOS, Apple Silicon. The Impeccable platform vocabulary does not currently include macOS; this project is not an iOS or web app.

## Stack

SwiftUI and native Liquid Glass, AVFoundation, Core Image, AVAssetWriter. FoyerKit (https://github.com/Belweave/FoyerKit) provides onboarding.

## Users

People using their iPhone as a Mac camera through Continuity Camera. The confirmed primary workflow is recording a camera + desk presentation. Monitoring, framing and sharing a clean presentation window remain supporting workflows.

## Product Purpose

An Apple Silicon camera studio that makes a face camera and Apple's overhead Desk View available together. Success means framing both sources, recording the composed presentation, taking snapshots, and finding recordings without leaving the app.

## Operating Context

The camera is supplied by macOS through Continuity Camera or another AVFoundation video device. Desk View depends on compatible hardware. Camera and optional microphone permission belong to the operating system. Video effects belong to macOS.

## Capabilities and Constraints

The requested scope includes camera discovery and selection, Desk View, recording, snapshots, layouts, framing, video effects and onboarding. Use public Apple APIs. Surface hardware capability and permission states honestly. A virtual-camera system extension and remote iPhone lens control are not confirmed requirements.

## Brand Commitments

The product title is `deskView()`. The public GitHub repository belongs to Belweave. SwiftUI and Liquid Glass are explicit visual requirements. FoyerKit is the required onboarding dependency.

## Evidence on Hand

- Apple Desk View guidance: https://support.apple.com/en-us/121541
- FoyerKit source: https://github.com/Belweave/FoyerKit
- User confirmed that image mockups precede interface implementation.

## Product Principles

- The recording should match the composed preview.
- Keep source setup and recording within one studio window.
- Keep recordings local and make the destination explicit.
- Report missing devices and permissions with a useful recovery action.

## Open Decisions

No licensing, pricing, App Store distribution, or virtual-camera requirement was supplied. Development choices and demonstration content must not be presented as user facts.
