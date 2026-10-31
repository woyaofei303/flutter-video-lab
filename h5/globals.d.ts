interface Window {
  LabBridge?: { postMessage(message: string): void }
  receiveFromHost?: (message: unknown) => Promise<void>
}
