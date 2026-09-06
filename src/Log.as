// Thin logging facade so call sites stay short and trace output is toggleable
// from Settings (S_Trace). Openplanet routes print/warn/error to the log window
// and to Openplanet.log.

namespace Log {
    void Info(const string &in msg)  { print("\\$5cf[AP] \\$z" + msg); }
    void Warn(const string &in msg)  { warn("[AP] " + msg); }
    void Error(const string &in msg) { error("[AP] " + msg); }

    // Only emitted when "Verbose protocol logging" is enabled.
    void Trace(const string &in msg) {
        if (S_Trace) print("\\$888[AP trace] \\$z" + msg);
    }
}
