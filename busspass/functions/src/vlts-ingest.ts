import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

export const ingestVltsData = functions.https.onRequest(async (req, res) => {
  // 1. Verify authentication (e.g. secret token)
  const token = req.headers.authorization?.split("Bearer ")[1];
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
  } catch (error) {
    console.error("Error ingesting VLTS data:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});
