#!/usr/bin/env python3
"""
Custom Nagios Plugin: check_system_metrics.py
INT333 Practical 8: Custom Python Monitoring Plugin for Nagios Core.
Monitors live CPU and Memory utilization of application nodes via /stats.
"""

import argparse
import json
import sys
import urllib.request


def main():
    parser = argparse.ArgumentParser(description="Nagios CPU & Memory Check Plugin")
    parser.add_argument("-H", "--host", default="127.0.0.1", help="Target host address")
    parser.add_argument("-p", "--port", type=int, default=8080, help="Target application port")
    parser.add_argument("-m", "--metric", choices=["cpu", "mem"], required=True, help="Metric to monitor (cpu|mem)")
    parser.add_argument("-w", "--warning", type=float, default=70.0, help="Warning threshold in percent")
    parser.add_argument("-c", "--critical", type=float, default=90.0, help="Critical threshold in percent")
    parser.add_argument("-t", "--timeout", type=int, default=5, help="HTTP timeout in seconds")
    args = parser.parse_args()

    url = f"http://{args.host}:{args.port}/stats"

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Nagios-Check/1.0"})
        with urllib.request.urlopen(req, timeout=args.timeout) as resp:
            if resp.status != 200:
                print(f"UNKNOWN - HTTP {resp.status} received from {url}")
                sys.exit(3)
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"CRITICAL - Failed to query {url}: {e}")
        sys.exit(2)

    if args.metric == "cpu":
        val = float(data.get("cpu_percent", 0.0))
        perfdata = f"cpu={val}%;{args.warning};{args.critical};0;100"
        if val >= args.critical:
            print(f"CRITICAL - CPU Utilization is {val}% (threshold: {args.critical}%) | {perfdata}")
            sys.exit(2)
        elif val >= args.warning:
            print(f"WARNING - CPU Utilization is {val}% (threshold: {args.warning}%) | {perfdata}")
            sys.exit(1)
        else:
            print(f"OK - CPU Utilization is {val}% | {perfdata}")
            sys.exit(0)

    elif args.metric == "mem":
        val = float(data.get("memory_percent", 0.0))
        used = data.get("memory_used_mb", 0)
        total = data.get("memory_total_mb", 0)
        perfdata = f"mem={val}%;{args.warning};{args.critical};0;100"
        if val >= args.critical:
            print(f"CRITICAL - Memory Utilization is {val}% ({used}MB / {total}MB) | {perfdata}")
            sys.exit(2)
        elif val >= args.warning:
            print(f"WARNING - Memory Utilization is {val}% ({used}MB / {total}MB) | {perfdata}")
            sys.exit(1)
        else:
            print(f"OK - Memory Utilization is {val}% ({used}MB / {total}MB) | {perfdata}")
            sys.exit(0)


if __name__ == "__main__":
    main()
