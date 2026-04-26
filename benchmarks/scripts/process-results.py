#!/usr/bin/env python3
"""Parse benchmark logs and write a compact Markdown report."""

import argparse
import datetime as dt
import pathlib
import re
from typing import Any, Dict, List, Optional, Tuple


BEGIN_RE = re.compile(r"^===== BEGIN BENCHMARK (?P<meta>.*?) =====$")
END_RE = re.compile(r"^===== END BENCHMARK (?P<meta>.*?) =====$")
NUMBER_RE = re.compile(r"^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$")


class Section:
    def __init__(self, source, name, meta, lines, status="unknown"):
        self.source = source
        self.name = name
        self.meta = meta
        self.lines = lines
        self.status = status
        self.suite = "unknown"
        self.rows = []
        self.summary_metric = ""
        self.summary_value = ""


def parse_meta(text: str) -> Dict[str, str]:
    meta = {}  # type: Dict[str, str]
    if " command=" in text:
        before, command = text.split(" command=", 1)
        text = before
        meta["command"] = command
    for token in text.split():
        if "=" in token:
            key, value = token.split("=", 1)
            meta[key] = value
    return meta


def collect_files(paths: List[pathlib.Path]) -> List[pathlib.Path]:
    files = []  # type: List[pathlib.Path]
    for path in paths:
        if path.is_dir():
            files.extend(sorted(p for p in path.rglob("*") if p.is_file() and p.suffix in {".log", ".out", ".txt"}))
        elif path.is_file():
            files.append(path)
    return files


def split_sections(path: pathlib.Path) -> List[Section]:
    lines = path.read_text(errors="replace").splitlines()
    sections = []  # type: List[Section]
    current_meta = None  # type: Optional[Dict[str, str]]
    current_lines = []  # type: List[str]

    for line in lines:
        begin = BEGIN_RE.match(line)
        if begin:
            if current_meta is not None:
                name = current_meta.get("name", path.stem)
                sections.append(Section(path, name, current_meta, current_lines))
            current_meta = parse_meta(begin.group("meta"))
            current_lines = [line]
            continue

        end = END_RE.match(line)
        if end and current_meta is not None:
            current_lines.append(line)
            end_meta = parse_meta(end.group("meta"))
            name = current_meta.get("name", path.stem)
            section = Section(path, name, current_meta, current_lines, status=end_meta.get("status", "unknown"))
            sections.append(section)
            current_meta = None
            current_lines = []
            continue

        if current_meta is not None:
            current_lines.append(line)

    if current_meta is not None:
        name = current_meta.get("name", path.stem)
        sections.append(Section(path, name, current_meta, current_lines))
    elif not sections and lines:
        sections.append(Section(path, path.stem, {"name": path.stem}, lines))

    return sections


def is_number(token: str) -> bool:
    return bool(NUMBER_RE.match(token))


def parse_osu(section: Section) -> bool:
    metric = ""
    rows = []  # type: List[Dict[str, Any]]

    for line in section.lines:
        if "Bandwidth (MB/s)" in line:
            metric = "bandwidth_mb_s"
            continue
        if "Avg Latency(us)" in line:
            metric = "latency_us"
            continue

        parts = line.split()
        if metric and len(parts) >= 2 and parts[0].isdigit() and is_number(parts[1]):
            row = {
                "size_b": int(parts[0]),
                metric: float(parts[1]),
            }
            if len(parts) >= 3 and parts[2] in {"Pass", "Fail"}:
                row["validation"] = parts[2]
            rows.append(row)

    if not rows:
        return False

    section.suite = "osu"
    section.rows = rows
    if metric == "bandwidth_mb_s":
        best = max(rows, key=lambda row: float(row["bandwidth_mb_s"]))
        section.summary_metric = "max bandwidth"
        section.summary_value = f"{best['bandwidth_mb_s']:.2f} MB/s at {best['size_b']} B"
    else:
        best = min(rows, key=lambda row: float(row["latency_us"]))
        section.summary_metric = "min latency"
        section.summary_value = f"{best['latency_us']:.2f} us at {best['size_b']} B"
    return True


def parse_nccl(section: Section) -> bool:
    rows = []  # type: List[Dict[str, Any]]
    saw_nccl = any("Collective test starting" in line or "all_reduce_perf" in line for line in section.lines)
    if not saw_nccl:
        return False

    for line in section.lines:
        parts = line.split()
        if len(parts) < 13 or not parts[0].isdigit() or not parts[1].isdigit():
            continue
        if not (is_number(parts[5]) and is_number(parts[6]) and is_number(parts[7]) and is_number(parts[9])):
            continue
        rows.append(
            {
                "size_b": int(parts[0]),
                "count": int(parts[1]),
                "type": parts[2],
                "redop": parts[3],
                "out_time_us": float(parts[5]),
                "out_algbw_gb_s": float(parts[6]),
                "out_busbw_gb_s": float(parts[7]),
                "out_wrong": int(parts[8]),
                "in_time_us": float(parts[9]),
                "in_algbw_gb_s": float(parts[10]),
                "in_busbw_gb_s": float(parts[11]),
                "in_wrong": int(parts[12]),
            }
        )

    if not rows:
        return False

    section.suite = "nccl"
    section.rows = rows
    best = max(rows, key=lambda row: float(row["in_busbw_gb_s"]))
    section.summary_metric = "max in-place busbw"
    section.summary_value = f"{best['in_busbw_gb_s']:.2f} GB/s at {best['size_b']} B"
    return True


def parse_nvshmem(section: Section) -> bool:
    rows = []  # type: List[Dict[str, Any]]
    saw_header = False

    for line in section.lines:
        if line.startswith("size(B)"):
            saw_header = True
            continue
        parts = line.split()
        if saw_header and len(parts) >= 7 and parts[0].isdigit() and parts[1].isdigit():
            if not (is_number(parts[4]) and is_number(parts[5]) and is_number(parts[6])):
                continue
            rows.append(
                {
                    "size_b": int(parts[0]),
                    "count": int(parts[1]),
                    "type": parts[2],
                    "scope": parts[3],
                    "latency_us": float(parts[4]),
                    "algbw_gb_s": float(parts[5]),
                    "busbw_gb_s": float(parts[6]),
                }
            )

    if not rows:
        return False

    section.suite = "nvshmem"
    section.rows = rows
    best = max(rows, key=lambda row: float(row["busbw_gb_s"]))
    section.summary_metric = "max busbw"
    section.summary_value = f"{best['busbw_gb_s']:.2f} GB/s at {best['size_b']} B ({best['type']} {best['scope']})"
    return True


def parse_section(section: Section) -> Section:
    for parser in (parse_osu, parse_nccl, parse_nvshmem):
        if parser(section):
            return section
    section.suite = section.meta.get("suite", "unknown")
    section.summary_metric = "parsed rows"
    section.summary_value = "0"
    return section


def markdown_table(headers: List[str], rows: List[List[str]]) -> List[str]:
    out = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    out.extend("| " + " | ".join(row) + " |" for row in rows)
    return out


def detail_rows(section: Section) -> Tuple[List[str], List[List[str]]]:
    if section.suite == "osu":
        first = section.rows[0]
        if "bandwidth_mb_s" in first:
            headers = ["Size (B)", "Bandwidth (MB/s)", "Validation"]
            rows = [[str(r["size_b"]), f"{r['bandwidth_mb_s']:.2f}", str(r.get("validation", ""))] for r in section.rows]
        else:
            headers = ["Size (B)", "Avg Latency (us)", "Validation"]
            rows = [[str(r["size_b"]), f"{r['latency_us']:.2f}", str(r.get("validation", ""))] for r in section.rows]
    elif section.suite == "nccl":
        headers = ["Size (B)", "Out Time (us)", "Out BusBW (GB/s)", "In Time (us)", "In BusBW (GB/s)", "Wrong"]
        rows = [
            [
                str(r["size_b"]),
                f"{r['out_time_us']:.2f}",
                f"{r['out_busbw_gb_s']:.2f}",
                f"{r['in_time_us']:.2f}",
                f"{r['in_busbw_gb_s']:.2f}",
                f"{r['out_wrong']}/{r['in_wrong']}",
            ]
            for r in section.rows
        ]
    elif section.suite == "nvshmem":
        headers = ["Size (B)", "Type", "Scope", "Latency (us)", "AlgBW (GB/s)", "BusBW (GB/s)"]
        rows = [
            [
                str(r["size_b"]),
                str(r["type"]),
                str(r["scope"]),
                f"{r['latency_us']:.2f}",
                f"{r['algbw_gb_s']:.2f}",
                f"{r['busbw_gb_s']:.2f}",
            ]
            for r in section.rows
        ]
    else:
        headers = ["Field", "Value"]
        rows = [["Rows parsed", str(len(section.rows))]]
    return headers, rows


def write_report(sections: List[Section], output: pathlib.Path) -> None:
    now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    lines = ["# Communication Benchmark Results", "", f"Generated: {now}", ""]

    summary_rows = []
    for section in sections:
        summary_rows.append(
            [
                section.name,
                section.suite,
                section.meta.get("provider", ""),
                section.status,
                str(len(section.rows)),
                section.summary_metric,
                section.summary_value,
                section.source.name,
            ]
        )

    lines.extend(markdown_table(["Benchmark", "Suite", "Provider", "Status", "Rows", "Metric", "Best", "Source"], summary_rows))

    for section in sections:
        lines.extend(["", f"## {section.name}", ""])
        command = section.meta.get("command")
        if command:
            lines.extend(["```bash", command, "```", ""])
        headers, rows = detail_rows(section)
        lines.extend(markdown_table(headers, rows))

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=pathlib.Path, help="Log files or directories to parse")
    parser.add_argument("-o", "--output", type=pathlib.Path, help="Markdown output path")
    args = parser.parse_args()

    files = collect_files(args.paths)
    sections = [parse_section(section) for path in files for section in split_sections(path)]
    if not sections:
        raise SystemExit("No benchmark logs found")

    output = args.output
    if output is None:
        first = args.paths[0]
        output = (first if first.is_dir() else first.parent) / "benchmark-report.md"

    write_report(sections, output)
    print(f"Wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
