#!/usr/bin/env python3
"""Build the health-gated rolling patching class deck."""
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.oxml.ns import qn

BG = RGBColor(0x0D, 0x11, 0x17)
PANEL = RGBColor(0x16, 0x1B, 0x22)
LINE = RGBColor(0x30, 0x36, 0x3D)
TEXT = RGBColor(0xE6, 0xED, 0xF3)
DIM = RGBColor(0x8B, 0x94, 0x9E)
CYAN = RGBColor(0x00, 0xD1, 0xFF)
GREEN = RGBColor(0x2E, 0xA0, 0x43)
GREEN_HI = RGBColor(0x3F, 0xB9, 0x50)
AMBER = RGBColor(0xF0, 0xB4, 0x29)

SW, SH = 13.333, 7.5
prs = Presentation()
prs.slide_width, prs.slide_height = Inches(SW), Inches(SH)
BLANK = prs.slide_layouts[6]


def slide():
    return prs.slides.add_slide(BLANK)


def bg(s, color=BG):
    s.background.fill.solid()
    s.background.fill.fore_color.rgb = color


def rect(s, x, y, w, h, fill=PANEL, line=LINE, line_w=1.0, round_=0.08):
    sh = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    sh.adjustments[0] = round_
    sh.fill.solid(); sh.fill.fore_color.rgb = fill
    sh.line.color.rgb = line; sh.line.width = Pt(line_w)
    sh.shadow.inherit = False
    return sh


def txt(s, x, y, w, h, runs, align=PP_ALIGN.LEFT, space_after=6, wrap=True):
    """runs: list of paragraphs; each paragraph is list of (text, size, color, bold)."""
    tb = s.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame
    tf.word_wrap = wrap
    for i, para in enumerate(runs):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.space_after = Pt(space_after)
        for (t, size, color, bold) in para:
            r = p.add_run(); r.text = t
            r.font.size = Pt(size); r.font.bold = bold
            r.font.color.rgb = color; r.font.name = "Consolas"
    return tb


def header(s, kicker, title, page=None):
    txt(s, 0.55, 0.28, 9.5, 0.3, [[(kicker, 11, CYAN, True)]])
    txt(s, 0.55, 0.55, 12.2, 0.9, [[(title, 30, TEXT, True)]])
    rect(s, 0.55, 1.42, 1.6, 0.045, fill=CYAN, line=CYAN)
    if page:
        txt(s, 12.35, 0.3, 0.45, 0.3, [[(f"{page:02d}", 11, DIM, True)]], align=PP_ALIGN.RIGHT)


def footer(s, left, right="HEALTH-GATED ROLLING PATCH"):
    txt(s, 0.55, 7.05, 8.5, 0.3, [[(left, 9, DIM, False)]])
    txt(s, 9.7, 7.05, 3.0, 0.3, [[(right, 9, DIM, True)]], align=PP_ALIGN.RIGHT)


def arrow(s, x1, y1, x2, y2, color=DIM, weight=2.0, dash=None):
    c = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    c.line.color.rgb = color
    c.line.width = Pt(weight)
    if dash:
        d = c.line._get_or_add_ln()
        pd = d.makeelement(qn('a:prstDash'), {'val': dash}); d.append(pd)
    # arrowhead
    ln = c.line._get_or_add_ln()
    head = ln.makeelement(qn('a:tailEnd'), {'type': 'triangle', 'w': 'med', 'len': 'med'})
    ln.append(head)
    return c


# ---------- Slide 1 — Title ----------
s = slide(); bg(s)
rect(s, 0, 0, SW, 0.12, fill=CYAN, line=CYAN)
txt(s, 0.8, 0.8, 12.5, 0.4, [[("DEV OPS PROJECT  ·  UNIVERSITY COURSE", 12, CYAN, True)]])
txt(s, 0.8, 1.7, 12.0, 3.2, [
    [("HEALTH-GATED", 64, TEXT, True)],
    [("ROLLING PATCH", 64, CYAN, True)],
])
txt(s, 0.8, 4.9, 11.5, 1.0, [
    [("How do you patch three servers without taking a website down?", 20, TEXT, False)],
    [("Terraform provisions  ·  Puppet configures  ·  Ansible orchestrates  ·  Nagios watches  ·  AWS ALB is the bouncer", 14, DIM, False)],
])
txt(s, 0.8, 6.6, 11.5, 0.4, [[("Presented by Batman   ·   ap-south-1   ·   http://health-gated-patching-alb-66842497.ap-south-1.elb.amazonaws.com/", 11, DIM, False)]])

# ---------- Slide 2 — The problem ----------
s = slide(); bg(s)
header(s, "01 · THE PROBLEM", "Maintenance that doesn't blink", 2)
rect(s, 0.55, 1.8, 6.0, 2.0)
txt(s, 0.8, 2.0, 5.5, 1.6, [
    [("99.9%", 54, AMBER, True)],
    [("availability = 44 minutes of downtime per year.", 14, TEXT, False)],
])
rect(s, 6.85, 1.8, 6.0, 2.0)
txt(s, 7.1, 2.0, 5.5, 1.6, [
    [("10 min", 54, TEXT, True)],
    [("to apt dist-upgrade + reboot one server — ×3 servers, done serially.", 14, TEXT, False)],
])
txt(s, 0.55, 4.15, 12.2, 2.2, [
    [("The question every operator answers with rituals:", 12, DIM, False)],
    [("Can I reboot this box right now?", 26, TEXT, True)],
    [("Answer it with a controlled loop, not with hope.", 16, CYAN, True)],
])
footer(s, "drain → patch → verify → re-admit  ·  and stop the moment a server can't prove it's healthy")

# ---------- Slide 3 — Architecture ----------
s = slide(); bg(s)
header(s, "02 · ARCHITECTURE", "Browser → ALB → three identical app servers", 3)
# Internet
rect(s, 5.4, 1.7, 2.5, 0.62, fill=PANEL, line=CYAN, line_w=2)
txt(s, 5.4, 1.82, 2.5, 0.4, [[("INTERNET", 14, CYAN, True)]], align=PP_ALIGN.CENTER)
arrow(s, 6.65, 2.32, 6.65, 3.0, CYAN, 2.4)
# VPC
rect(s, 0.55, 3.0, 12.25, 3.35, fill=RGBColor(0x10, 0x15, 0x1D), line=LINE)
txt(s, 0.75, 3.08, 6.0, 0.3, [[("VPC 10.20.0.0/16   ·   2 AZs   ·   public subnets", 10, DIM, True)]])
# ALB
rect(s, 4.6, 3.5, 4.15, 0.9, fill=PANEL, line=CYAN, line_w=2)
txt(s, 4.6, 3.58, 4.15, 0.35, [[("ALB  :80", 15, CYAN, True)]], align=PP_ALIGN.CENTER)
txt(s, 4.6, 3.9, 4.15, 0.3, [[("health-gated-patching-alb", 10, DIM, False)]], align=PP_ALIGN.CENTER)
arrow(s, 6.65, 4.4, 6.65, 5.0, DIM, 2.0)
txt(s, 6.75, 4.55, 6.0, 0.3, [[("HTTP :8080  →  healthy targets only", 9, DIM, False)]])
# 3 app servers
xs = [1.15, 4.4, 7.65]
labels = ["APP-1", "APP-2", "APP-3"]
ips = ["10.20.1.89", "10.20.2.104", "10.20.1.200"]
for i in range(3):
    rect(s, xs[i], 5.0, 2.55, 1.15, fill=PANEL, line=LINE)
    txt(s, xs[i], 5.08, 2.55, 0.35, [[(labels[i] + "   ", 15, GREEN_HI, True), ("●", 12, GREEN_HI, True)]], align=PP_ALIGN.CENTER)
    txt(s, xs[i], 5.43, 2.55, 0.3, [[(ips[i], 11, TEXT, False)]], align=PP_ALIGN.CENTER)
    txt(s, xs[i], 5.72, 2.55, 0.3, [[("health-app :8080", 9, DIM, False)]], align=PP_ALIGN.CENTER)
# Nagios
rect(s, 10.35, 3.5, 2.15, 0.9, fill=PANEL, line=AMBER, line_w=1.5)
txt(s, 10.35, 3.58, 2.15, 0.3, [[("NAGIOS", 12, AMBER, True)]], align=PP_ALIGN.CENTER)
txt(s, 10.35, 3.88, 2.15, 0.3, [[("checks · alerts", 9, DIM, False)]], align=PP_ALIGN.CENTER)
arrow(s, 10.35, 4.4, 9.2, 5.35, AMBER, 1.5, dash='dash')
txt(s, 9.0, 4.75, 3.4, 0.3, [[("checks :8080 / :22", 9, AMBER, False)]])
txt(s, 0.75, 6.45, 12.0, 0.3, [[("Target group requires HTTP 200 on /health · no public HTTP on servers · SSH only from operator CIDR (128.185.168.199/32)", 10, DIM, False)]])
footer(s, "official AWS icon set in handout; arrows = traffic, dashed = monitoring")

# ---------- Slide 4 — The loop ----------
s = slide(); bg(s)
header(s, "03 · THE ROLLING PATCH LOOP", "Nine gates. One at a time.", 4)
steps = [
    ("1", "confirm", "confirm_patch=true + target-group ARN required"),
    ("2", "verify", "server must belong to the Terraform-managed target group"),
    ("3", "in progress", "recorded in patch-report.json"),
    ("4", "deregister", "server removed from ALB — stops receiving traffic"),
    ("5", "drain wait", "wait until ALB reports state = unused"),
    ("6", "patch", "apt dist-upgrade · reboot only if /var/run/reboot-required exists"),
    ("7", "verify", "SSH returns → fresh curl /health over SSH must return 200"),
    ("8", "re-register", "back into the ALB · wait until state = healthy"),
    ("9", "record", "server marked patched · only then does server 2 begin"),
]
for i, (n, name, desc) in enumerate(steps):
    yy = 1.75 + i * 0.52
    rect(s, 0.55, yy, 0.55, 0.44, fill=(CYAN if i % 2 == 0 else PANEL), line=CYAN, round_=0.5)
    txt(s, 0.55, yy + 0.045, 0.55, 0.35, [[(n, 15, BG if i % 2 == 0 else CYAN, True)]], align=PP_ALIGN.CENTER)
    txt(s, 1.3, yy + 0.005, 2.15, 0.4, [[(name.upper(), 12, TEXT, True)]])
    txt(s, 3.5, yy + 0.005, 9.3, 0.45, [[(desc, 12, DIM, False)]])
footer(s, "serial: 1  ·  any_errors_fatal: true  ·  at most one server out of rotation, ever")

# ---------- Slide 5 — Draining trick ----------
s = slide(); bg(s)
header(s, "04 · WHY THE DRAIN MATTERS", "One server leaves, two keep serving", 5)
def triple(y, active, patching_idx, title):
    txt(s, 0.6, y - 0.35, 6.0, 0.3, [[(title, 12, DIM, True)]])
    labels = ["APP-1", "APP-2", "APP-3"]
    for i, lab in enumerate(labels):
        on = (i != patching_idx)
        fill = PANEL if on else RGBColor(0x1A, 0x16, 0x0C)
        line = GREEN if on else AMBER
        x = 0.6 + i * 2.6
        rect(s, x, y, 2.3, 1.35, fill=fill, line=line, line_w=2)
        status = "SERVING" if on else "DRAINED"
        col = GREEN_HI if on else AMBER
        txt(s, x, y + 0.12, 2.3, 0.35, [[(lab, 15, TEXT, True)]], align=PP_ALIGN.CENTER)
        txt(s, x, y + 0.5, 2.3, 0.35, [[("● " + status, 13, col, True)]], align=PP_ALIGN.CENTER)
        txt(s, x, y + 0.85, 2.3, 0.3, [[("healthy" if on else "out of rotation", 9, DIM, False)]], align=PP_ALIGN.CENTER)
triple(2.35, None, None, "BEFORE — all three serving (ELB round-robin)")
triple(4.85, None, 1, "DURING — APP-2 drained for patching")
txt(s, 0.6, 6.55, 12.2, 0.4, [[("Zero user-visible errors: ALB health-gates targets 10s × 2. A patched server re-enters only when it proves itself.", 13, TEXT, False)]])
footer(s, "target group health check: GET /health → expect 200")

# ---------- Slide 6 — The gate ----------
s = slide(); bg(s)
header(s, "05 · THE GATE", "Fresh proof beats stale status", 6)
rect(s, 0.55, 1.8, 6.0, 3.4)
txt(s, 0.8, 1.95, 5.5, 0.4, [[("ANSIBLE'S CHECK  ·  THE GATE", 12, CYAN, True)]])
for i, l in enumerate(["runs inside the server, over SSH", "http://127.0.0.1:8080/health", "must return exactly 200", "checked right now — before re-admittance", "single source of truth for rollout"]):
    txt(s, 0.8, 2.45 + i * 0.62, 5.5, 0.5, [[("→  ", 13, CYAN, True), (l, 13, TEXT, False)]])
rect(s, 6.85, 1.8, 6.0, 3.4)
txt(s, 7.1, 1.95, 5.5, 0.4, [[("NAGIOS  ·  THE WITNESS", 12, AMBER, True)]])
for i, l in enumerate(["independent monitoring by design", "polls on an interval — can lag minutes", "alerts identify host + service + output", "65/65 checks OK after build", "does NOT gate the rollout"]):
    txt(s, 7.1, 2.45 + i * 0.62, 5.5, 0.5, [[("→  ", 13, AMBER, True), (l, 13, TEXT, False)]])
footer(s, "gate = Ansible fresh check   ·   Nagios = after-the-fact corroboration")

# ---------- Slide 7 — Failure path ----------
s = slide(); bg(s)
header(s, "06 · IF IT CANNOT PROVE ITSELF", "Rollout halts. Server stays out.", 7)
arr = [("inject 503", "failure demo marker file"),
       ("drain", "APP-2 deregistered"),
       ("patch + reboot", "updates applied, rebooted"),
       ("health gate", "curl /health → 503"),
       ("HALT", "report written · no re-register")]
for i, (a, b) in enumerate(arr):
    x = 0.55 + i * 2.52
    last = (i == len(arr) - 1)
    rect(s, x, 2.6, 2.15, 1.6, fill=(RGBColor(0x1F, 0x0D, 0x0D) if last else PANEL), line=(RGBColor(0xF8, 0x51, 0x49) if last else LINE), line_w=2)
    txt(s, x + 0.1, 2.72, 1.95, 0.7, [[(a.upper(), 14, (RGBColor(0xF8,0x51,0x49) if last else TEXT), True)]])
    txt(s, x + 0.1, 3.3, 1.95, 0.8, [[(b, 10, DIM, False)]])
    if i < len(arr) - 1:
        arrow(s, x + 2.15, 3.4, x + 2.48, 3.4, DIM, 2.0)
txt(s, 0.55, 4.7, 12.3, 1.6, [
    [("What the report says:", 12, DIM, False)],
    [("failed: 13.203.203.4  ·  step: health_check  ·  not attempted: APP-1, APP-3", 16, TEXT, True)],
    [("The ALB keeps serving from APP-1 and APP-3. Recovery = operator action, not automation.", 13, DIM, False)],
])
footer(s, "demo on demand: failure_demo.yml inject|restore")

# ---------- Slide 8 — Separation of concerns ----------
s = slide(); bg(s)
header(s, "07 · SEPARATION OF CONCERNS", "Four tools. Four jobs.", 8)
rows = [
    ("Terraform", "infrastructure", "VPC, ALB, target group, 4 EC2, security groups, outputs", "owns the lab's existence"),
    ("Puppet", "desired state", "required packages, systemd unit, service enabled+running", "never upgrades the OS"),
    ("Ansible", "orchestration", "bootstrap, serial patch loop, ALB drain/register, reports", "imperative, ordered, gated"),
    ("Nagios", "monitoring", "ALB + per-host HTTP/SSH/disk/load, alerts", "observes; does not gate"),
    ("AWS ALB", "traffic + gate", "round-robin to healthy targets; deregister/drain/re-register", "enforces HTTP 200 on /health"),
]
for i, (a, b, c, d) in enumerate(rows):
    y = 1.85 + i * 0.9
    rect(s, 0.55, y, 2.5, 0.78)
    txt(s, 0.7, y + 0.1, 2.2, 0.55, [[(a, 15, CYAN, True)]])
    rect(s, 3.15, y, 2.0, 0.78, fill=BG, line=LINE)
    txt(s, 3.25, y + 0.12, 1.8, 0.5, [[(b, 11, TEXT, True)]])
    txt(s, 5.35, y + 0.02, 7.5, 0.35, [[(c, 10, TEXT, False)]])
    txt(s, 5.35, y + 0.35, 7.5, 0.35, [[(d, 10, DIM, False)]])
footer(s, "Puppet drift-checks the service · Ansible sequences the work · Nagios watches everything")

# ---------- Slide 9 — Security ----------
s = slide(); bg(s)
header(s, "08 · SECURITY MODEL", "Nothing on the internet has to trust anything", 9)
items = [
    ("SSH", "operator CIDR only — 0.0.0.0/0 is rejected by Terraform validation"),
    ("App HTTP", "no public ingress. Only ALB SG (app port) and Nagios SG may reach it"),
    ("ALB", "internet-facing :80 only — deliberate for the demo"),
    ("Nagios UI", "operator CIDR + loopback only; packaged Apache config restricts to RFC1918"),
    ("Secrets", "none in the repo — .gitignore for state, tfvars, keys, reports"),
    ("Blast radius", "everything tagged Project=health-gated-patching + Lab=true; Ansible inventory filters by tag"),
    ("Automation gates", "confirm_patch=true and confirm_failure_injection=true required; failure demo opt-in, never default"),
]
for i, (a, b) in enumerate(items):
    y = 1.9 + i * 0.68
    txt(s, 0.7, y, 2.3, 0.6, [[(a.upper(), 12, CYAN, True)]])
    txt(s, 3.1, y, 9.6, 0.65, [[(b, 12, TEXT, False)]])
footer(s, "answers if asked: 'why can't anyone curl the app directly?'")

# ---------- Slide 10 — Demo plan ----------
s = slide(); bg(s)
header(s, "09 · LIVE DEMO", "Six minutes, zero edits", 10)
demo = [
    ("0:00", "Open ALB URL — hit /health, then / — show HTML with hostname + version"),
    ("0:30", "Reload x6 — hostname rotates across all three instances (load balancing)"),
    ("1:00", "Show ALB target group: 3 × healthy via AWS CLI"),
    ("1:30", "Run patch.yml — one server drains, patches, returns; watch two stay up"),
    ("3:30", "Show patch-report.json — patched list, before/after"),
    ("4:30", "Optional failure demo: inject 503, re-run patch → rollout halts HERE"),
    ("5:30", "Restore marker, re-run → all three re-admitted healthy; Nagios all-green"),
]
for i, (t, d) in enumerate(demo):
    y = 1.9 + i * 0.68
    rect(s, 0.55, y, 1.15, 0.55, fill=PANEL, line=LINE, round_=0.5)
    txt(s, 0.55, y + 0.09, 1.15, 0.4, [[(t, 12, CYAN, True)]], align=PP_ALIGN.CENTER)
    txt(s, 1.9, y + 0.09, 10.8, 0.5, [[(d, 13, TEXT, False)]])
footer(s, "rehearse once with the lab up: apply → bootstrap → demo → destroy")

# ---------- Slide 11 — Failure matrix ----------
s = slide(); bg(s)
header(s, "10 · FAILURE MATRIX", "Every failure is a controlled stop", 11)
matrix = [
    ("Drain never completes", "Wait for 'unused' exceeds retries (3 min)", "halt before touching OS", "operator investigates target group"),
    ("apt fails", "dist-upgrade returns non-zero", "halt at apt step", "fix packages / hold, re-run"),
    ("Reboot hangs", "wait_for_connection > 600s", "halt at wait for SSH", "power cycle via console if needed"),
    ("Health check 503", "curl returns ≠200 × 24 retries", "halt at health_check", "server left OUT of target group — manual repair"),
    ("ALB never sees healthy", "healthy wait exceeds 4 min", "halt at wait_for_healthy", "check app logs, re-register manually if fixed"),
    ("Mid-run AWS API error", "describe-target-health fails", "halt at that step", "credentials/region check, re-run"),
]
for i, (a, b, c, d) in enumerate(matrix):
    y = 1.75 + i * 0.82
    txt(s, 0.55, y + 0.03, 3.05, 0.7, [[(a, 11, AMBER, True)]])
    txt(s, 3.7, y + 0.03, 3.4, 0.7, [[(b, 10, DIM, False)]])
    txt(s, 7.15, y + 0.03, 2.3, 0.7, [[(c, 10, TEXT, False)]])
    txt(s, 9.5, y + 0.03, 3.3, 0.7, [[(d, 10, DIM, False)]])
txt(s, 0.55, 6.75, 12.0, 0.3, [[("Applies to 13.203.203.4 in the live run: drain production patched with zero ALB errors", 10, DIM, False)]])
footer(s, "every row ends the same way: stop · report · manual recovery")

# ---------- Slide 12 — What I would NOT claim ----------
s = slide(); bg(s)
header(s, "11 · WHAT THIS IS NOT", "Claims I refuse to make", 12)
refuses = [
    ("“It auto-rolls-back OS updates.”", "It doesn't. It stops safely and reports — rollback is an operator action."),
    ("“It's production.”", "It's a learning lab: 4 small instances, one region, tiny app. The architecture is real; the scale is not."),
    ("“Nagios verified the rollout.”", "Nagios watches and alerts; the gate is Ansible's fresh health check."),
    ("“It's highly available.”", "2 AZs, no redundancy of the ALB itself, no autoscaling — by design."),
    ("“AI generated this.”", "AI helped draft; every claim here is backed by a command you saw me run."),
]
for i, (a, b) in enumerate(refuses):
    y = 1.9 + i * 1.0
    txt(s, 0.6, y, 6.2, 0.9, [[(a, 15, TEXT, True)]])
    txt(s, 7.0, y, 5.8, 0.95, [[(b, 13, DIM, False)]])
footer(s, "judgment > enthusiasm")

# ---------- Slide 13 — Rubric alignment ----------
s = slide(); bg(s)
header(s, "12 · RUBRIC", "The end-to-end combo, mapped", 13)
tools = [
    ("Terraform", "infrastructure as code", "terraform apply → 13 resources · outputs real"),
    ("Puppet", "configuration management", "puppet apply → packages, unit, service running on all 3 nodes"),
    ("Ansible", "deployment + orchestration", "bootstrap + patch playbook → serial gated rollout, observed"),
    ("Nagios", "continuous monitoring", "65/65 checks OK; ALB + per-host HTTP/SSH/disk/load"),
]
for i, (a, b, c) in enumerate(tools):
    y = 1.85 + i * 1.05
    rect(s, 0.55, y, 2.2, 0.9, fill=PANEL, line=CYAN)
    txt(s, 0.7, y + 0.1, 1.9, 0.35, [[(a.upper(), 15, CYAN, True)]])
    txt(s, 0.7, y + 0.45, 1.9, 0.35, [[(b, 9, DIM, False)]])
    arrow(s, 2.75, y + 0.45, 3.25, y + 0.45, DIM, 2.0)
    txt(s, 3.4, y + 0.05, 9.3, 0.8, [[(c, 13, TEXT, False)]])
txt(s, 0.55, 6.35, 12.3, 0.4, [[("Row: Puppet + Terraform + Ansible + Nagios — end-to-end DevOps project.", 13, TEXT, True)]])
footer(s, "evidence: live run log, target-health table, report JSON, Nagios status page")

# ---------- Slide 14 — Closing ----------
s = slide(); bg(s)
rect(s, 0, 0, SW, 0.12, fill=CYAN, line=CYAN)
txt(s, 0.8, 1.3, 12.0, 0.4, [[("CLOSING", 12, CYAN, True)]])
txt(s, 0.8, 2.0, 12.2, 2.6, [
    [("Drain it.", 58, TEXT, True)],
    [("Patch it.", 58, CYAN, True)],
    [("Prove it. Roll it back — or roll it out.", 58, TEXT, True)],
])
txt(s, 0.8, 5.35, 12.0, 1.2, [
    [("The whole project in four words:", 15, DIM, False)],
    [("stop when a server can't prove itself.", 26, TEXT, True)],
])
footer(s, "thank you  ·  questions?", "HEALTH-GATED ROLLING PATCH")

out = "/home/batman/Documents/GitHub/devops333/docs/health-gated-patching.pptx"
prs.save(out)
print("saved", out)
