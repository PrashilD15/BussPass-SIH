"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.ingestVltsData = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
exports.ingestVltsData = functions.https.onRequest(async (req, res) => {
    var _a;
    // 1. Verify authentication (e.g. secret token)
    const token = (_a = req.headers.authorization) === null || _a === void 0 ? void 0 : _a.split("Bearer ")[1];
    const expectedToken = process.env.VLTS_API_TOKEN || "DEFAULT_SECRET_TOKEN";
    if (token !== expectedToken) {
        res.status(401).json({ error: "Unauthorized" });
        return;
    }
    // 2. Validate payload (assuming array of bus updates)
    const updates = req.body.buses;
    if (!Array.isArray(updates)) {
        res.status(400).json({ error: "Invalid payload format, expected 'buses' array." });
        return;
    }
    try {
        const db = admin.database();
        // 3. Process each update
        const promises = updates.map(async (bus) => {
            const { busId, lat, lng, speed, heading, routeId, nextStopId } = bus;
            if (!busId || lat === undefined || lng === undefined) {
                return Promise.resolve(); // Skip invalid records
            }
            const busRef = db.ref(`buses/${busId}`);
            return busRef.set({
                lat,
                lng,
                speed: speed || 0,
                heading: heading || 0,
                routeId: routeId || null,
                nextStopId: nextStopId || null,
                lastUpdated: admin.database.ServerValue.TIMESTAMP,
                source: "STC_VLTS"
            });
        });
        await Promise.all(promises);
        res.status(200).json({ success: true, count: promises.length });
    }
    catch (error) {
        console.error("Error ingesting VLTS data:", error);
        res.status(500).json({ error: "Internal server error" });
    }
});
//# sourceMappingURL=vlts-ingest.js.map