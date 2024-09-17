declare module "brevis-sdk-typescript" {
    export class Field {
      constructor(params: {
        contract: string;
        log_index: number;
        event_id: string;
        is_topic: boolean;
        field_index: number;
        value: string;
      });
    }
  
    export class ReceiptData {
      constructor(params: {
        block_num: number;
        tx_hash: string;
        fields: Field[];
      });
    }
  
    export class ProofRequest {
      addReceipt(receiptData: ReceiptData): void;
      setCustomInput(input: any): void;
    }
  
    export function asBytes32(value: string): string;
  
    export class ProveResponse {
      static fromObject(obj: any): ProveResponse;
      err: { msg: string } | null;
      proof: string;
      circuit_info: any;
    }
  }
  