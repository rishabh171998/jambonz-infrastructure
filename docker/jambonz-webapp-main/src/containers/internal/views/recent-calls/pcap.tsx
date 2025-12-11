import React, { useEffect, useState } from "react";

import { getPcap } from "src/api";

import type { DownloadedBlob, RecentCall } from "src/api/types";
import { useToast } from "src/components/toast/toast-provider";

type PcapButtonProps = {
  call: RecentCall;
};

export const PcapButton = ({ call }: PcapButtonProps) => {
  const { toastError } = useToast();
  const [pcap, setPcap] = useState<DownloadedBlob | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!pcap && !loading && !error) {
      setLoading(true);
      // Homer stores calls by SIP Call-ID, not call_sid
      // The API endpoint accepts sip_callid which Homer uses to look up the call
      const callId = call.sip_callid || call.call_sid;
      
      if (!callId) {
        setError("No call ID available");
        setLoading(false);
        return;
      }

      getPcap(call.account_sid, callId, "invite")
        .then(({ blob, status }) => {
          setLoading(false);
          if (blob) {
            setPcap({
              data_url: URL.createObjectURL(blob),
              file_name: `callid-${callId}.pcap`,
            });
          } else {
            // pcap might not be available for this call
            if (status === 400 || status === 404) {
              setError("PCAP not available for this call");
            } else {
              setError("Failed to load PCAP");
            }
          }
        })
        .catch((error) => {
          setLoading(false);
          const errorMsg = error.msg || error.message || "Failed to download PCAP";
          
          // Check if it's a Homer configuration error
          if (error.status === 400 || errorMsg.includes("Homer") || errorMsg.includes("homer") || errorMsg.includes("API token")) {
            setError("PCAP requires Homer to be configured");
          } else if (error.status === 404 || errorMsg.includes("not available") || errorMsg.includes("404")) {
            setError("PCAP not available for this call");
          } else {
            setError("PCAP unavailable");
          }
          
          // Only show toast for unexpected errors
          if (error.status !== 400 && error.status !== 404) {
            toastError(errorMsg);
          }
        });
    }
  }, [call, pcap, loading, error, toastError]);

  if (pcap) {
    return (
      <a
        href={pcap.data_url}
        download={pcap.file_name}
        className="btn btn--small pcap"
      >
        Download pcap
      </a>
    );
  }

  if (loading) {
    return (
      <span className="btn btn--small pcap" style={{ opacity: 0.6 }}>
        Loading...
      </span>
    );
  }

  if (error) {
    return (
      <span className="btn btn--small pcap" style={{ opacity: 0.6, cursor: "not-allowed" }} title={error}>
        PCAP unavailable
      </span>
    );
  }

  return null;
};
