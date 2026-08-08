import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Content-Type": "application/json",
};

const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: cors });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authHeader = req.headers.get("Authorization") || "";
    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return reply({ error: "Sign in is required." }, 401);
    const actorId = authData.user.id;
    const { data: actorProfile } = await admin
      .from("profiles").select("id,email,display_name,state").eq("id", actorId).single();
    if (!actorProfile || actorProfile.state !== "active") return reply({ error: "Account access is inactive." }, 403);
    const { data: platform } = await admin
      .from("platform_memberships").select("role").eq("user_id", actorId).maybeSingle();
    const { data: memberships } = await admin
      .from("dealership_memberships").select("dealership_id,role,state").eq("user_id", actorId);
    const platformRole = platform?.role || "";
    const body = await req.json();
    const action = String(body.action || "");

    const elevatedPlatform = ["master", "lotcaster_general_manager"].includes(platformRole);
    const supportPlatform = ["master", "lotcaster_general_manager", "lotcaster_manager", "lotcaster_support"].includes(platformRole);
    const activeMemberships = (memberships || []).filter((m) => m.state === "active");
    const manageableMembership = activeMemberships.find((m) => ["owner", "manager"].includes(m.role));

    async function currentDealershipId() {
      if (body.dealershipId) return String(body.dealershipId);
      if (manageableMembership) return manageableMembership.dealership_id;
      if (supportPlatform) {
        const { data: supported } = await admin.from("support_assignments")
          .select("dealership_id").eq("user_id", actorId).is("ended_at", null).limit(1);
        if (supported?.[0]) return supported[0].dealership_id;
      }
      if (elevatedPlatform) {
        const { data: first } = await admin.from("dealerships").select("id").order("created_at").limit(1);
        if (first?.[0]) return first[0].id;
      }
      return "";
    }

    async function mayManage(dealershipId: string) {
      if (elevatedPlatform) return true;
      if (supportPlatform) {
        const { data } = await admin.from("support_assignments").select("dealership_id")
          .eq("user_id", actorId).eq("dealership_id", dealershipId).is("ended_at", null).maybeSingle();
        if (data) return true;
      }
      return activeMemberships.some((m) =>
        m.dealership_id === dealershipId && ["owner", "manager"].includes(m.role));
    }

    async function teamSummary(dealershipId: string) {
      const { data: teamRows, error } = await admin.from("dealership_memberships")
        .select("user_id,role,state,profiles!dealership_memberships_user_id_fkey(id,email,display_name,state)")
        .eq("dealership_id", dealershipId).in("role", ["manager", "salesperson"]);
      if (error) throw error;
      const users = (teamRows || []).map((row: any) => ({
        id: row.user_id,
        name: row.profiles?.display_name || row.profiles?.email || "Team member",
        email: row.profiles?.email || "",
        role: row.role,
        status: row.state === "active" && row.profiles?.state === "active" ? "active" : "inactive",
        assigned: 0, prepared: 0, posted: 0, overdue: 0,
      }));
      const { data: events } = await admin.from("audit_events")
        .select("id,event_type,reason,occurred_at,actor_id")
        .eq("dealership_id", dealershipId).order("occurred_at", { ascending: false }).limit(100);
      return {
        dealershipId,
        users,
        activity: (events || []).map((event: any) => ({
          id: String(event.id), type: event.event_type, details: event.reason || "",
          userId: event.actor_id || "", createdAt: event.occurred_at,
        })),
        totals: { assigned: 0, prepared: 0, posted: 0, unassigned: 0 },
      };
    }

    if (action === "list_dealers") {
      if (!elevatedPlatform) return reply({ error: "Dealer administration access is required." }, 403);
      const { data, error } = await admin.from("dealerships")
        .select("id,name,contact_email,subscription_plan,state,billing_state,created_at").order("name");
      if (error) throw error;
      return reply({ dealers: (data || []).map((d: any) => ({
        id: d.id, name: d.name, ownerEmail: d.contact_email || "",
        plan: d.subscription_plan || "pilot", status: d.state === "active" ? "active" : "suspended",
        expiresAt: null, notes: d.billing_state || "",
      })) });
    }

    if (action === "create_dealer") {
      if (!elevatedPlatform) return reply({ error: "Dealer administration access is required." }, 403);
      const name = String(body.name || "").trim();
      const email = String(body.ownerEmail || "").trim().toLowerCase();
      if (!name || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
        return reply({ error: "Enter a dealership name and valid owner email." }, 400);
      }
      const { error } = await admin.from("dealerships").insert({
        name, contact_email: email, subscription_plan: String(body.plan || "pilot"),
        state: "active", created_by: actorId,
      });
      if (error) throw error;
      return await rerun("list_dealers");
    }

    if (action === "set_dealer_state") {
      if (!elevatedPlatform) return reply({ error: "Dealer administration access is required." }, 403);
      const state = body.status === "suspended" ? "deactivated" : "active";
      const { error } = await admin.from("dealerships").update({ state }).eq("id", String(body.id || ""));
      if (error) throw error;
      return await rerun("list_dealers");
    }

    const dealershipId = await currentDealershipId();
    if (!dealershipId || !(await mayManage(dealershipId))) {
      return reply({ error: "No manageable dealership is available for this account." }, 403);
    }
    if (action === "list_team") return reply(await teamSummary(dealershipId));

    if (action === "invite_team_user") {
      const role = body.role === "manager" ? "manager" : "salesperson";
      const actorDealerRole = activeMemberships.find((m) => m.dealership_id === dealershipId)?.role;
      if (actorDealerRole === "manager" && role !== "salesperson") {
        return reply({ error: "Managers may only invite salespeople." }, 403);
      }
      const email = String(body.email || "").trim().toLowerCase();
      const name = String(body.name || "").trim();
      if (!name || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
        return reply({ error: "Enter a name and valid email address." }, 400);
      }
      const redirectTo = "http://127.0.0.1:5173/";
      const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
        redirectTo, data: { display_name: name },
      });
      if (inviteError) throw inviteError;
      const userId = invited.user.id;
      await admin.from("profiles").update({
        display_name: name, state: "active", must_change_password: false,
      }).eq("id", userId);
      const { error: memberError } = await admin.from("dealership_memberships").upsert({
        dealership_id: dealershipId, user_id: userId, role, state: "active",
        invited_by: actorId, activated_at: new Date().toISOString(),
      });
      if (memberError) throw memberError;
      await admin.from("audit_events").insert({
        dealership_id: dealershipId, actor_id: actorId, assisted_user_id: userId,
        event_type: "user_created", entity_type: "profile", entity_id: userId,
        reason: `${name} invited as ${role}`,
      });
      return reply(await teamSummary(dealershipId));
    }

    const targetId = String(body.id || "");
    const { data: targetMembership } = await admin.from("dealership_memberships")
      .select("role,user_id").eq("dealership_id", dealershipId).eq("user_id", targetId).maybeSingle();
    if (!targetMembership) return reply({ error: "Team member was not found." }, 404);
    const actorDealerRole = activeMemberships.find((m) => m.dealership_id === dealershipId)?.role;
    if (actorDealerRole === "manager" && targetMembership.role !== "salesperson") {
      return reply({ error: "Managers may only manage salespeople." }, 403);
    }

    if (action === "set_user_state") {
      const active = body.status !== "inactive";
      const now = new Date();
      const { error } = await admin.from("dealership_memberships").update({
        state: active ? "active" : "deactivated",
        activated_at: active ? now.toISOString() : null,
        deactivated_at: active ? null : now.toISOString(),
        release_assignments_at: active ? null : new Date(now.getTime() + 48 * 3600_000).toISOString(),
      }).eq("dealership_id", dealershipId).eq("user_id", targetId);
      if (error) throw error;
      if (active) {
        await admin.from("profiles").update({
          state: "active", deactivated_at: null, anonymize_after: null,
        }).eq("id", targetId);
      } else {
        const { count: otherActiveDealerships } = await admin.from("dealership_memberships")
          .select("dealership_id", { count: "exact", head: true })
          .eq("user_id", targetId).eq("state", "active").neq("dealership_id", dealershipId);
        const { data: targetPlatformRole } = await admin.from("platform_memberships")
          .select("user_id").eq("user_id", targetId).maybeSingle();
        if (!otherActiveDealerships && !targetPlatformRole) {
          await admin.from("profiles").update({
            state: "deactivated",
            deactivated_at: now.toISOString(),
            anonymize_after: new Date(now.getTime() + 30 * 86400_000).toISOString(),
          }).eq("id", targetId);
        }
      }
      return reply(await teamSummary(dealershipId));
    }

    if (action === "send_password_reset") {
      const { data: target } = await admin.from("profiles").select("email").eq("id", targetId).single();
      if (!target?.email) return reply({ error: "Team member email was not found." }, 404);
      const publicClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!);
      const { error } = await publicClient.auth.resetPasswordForEmail(target.email, {
        redirectTo: "http://127.0.0.1:5173/",
      });
      if (error) throw error;
      return reply(await teamSummary(dealershipId));
    }

    return reply({ error: "Unknown management action." }, 400);

    async function rerun(nextAction: string) {
      if (nextAction === "list_dealers") {
        const { data, error } = await admin.from("dealerships")
          .select("id,name,contact_email,subscription_plan,state,billing_state,created_at").order("name");
        if (error) throw error;
        return reply({ dealers: (data || []).map((d: any) => ({
          id: d.id, name: d.name, ownerEmail: d.contact_email || "",
          plan: d.subscription_plan || "pilot", status: d.state === "active" ? "active" : "suspended",
          expiresAt: null, notes: d.billing_state || "",
        })) });
      }
      return reply({ error: "Invalid action." }, 400);
    }
  } catch (error) {
    return reply({ error: error instanceof Error ? error.message : String(error) }, 400);
  }
});
