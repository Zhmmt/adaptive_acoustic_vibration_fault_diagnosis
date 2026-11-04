#!/usr/bin/env python3
"""Capture real 115200 UART output with PC timestamps. No motor control commands."""
import argparse,datetime,sys,time

def now():
    return datetime.datetime.now().astimezone().isoformat(timespec="milliseconds")

def main():
    p=argparse.ArgumentParser(description="RS555 read-only UART logging")
    p.add_argument("--port",required=True,help="COM6 or another actual serial port")
    p.add_argument("--baud",type=int,default=115200)
    p.add_argument("--duration",type=float,default=120)
    p.add_argument("--output",required=True)
    p.add_argument("--start-live",action="store_true",help="send 's' to request Vitis live text output; no motor start")
    args=p.parse_args()
    try: import serial
    except ImportError:
        sys.exit("Missing pyserial: python -m pip install pyserial")
    import pathlib
    output=pathlib.Path(args.output); output.parent.mkdir(parents=True,exist_ok=True)
    try:
        with serial.Serial(args.port,args.baud,timeout=0.5) as port, output.open('w',encoding='utf-8',newline='') as f:
            header=f'# UART log: {now()} port={args.port} baud={args.baud}; content is raw received text with PC timestamps\n'
            f.write(header); print(header,end='')
            time.sleep(0.5)
            if args.start_live:
                port.write(b's');port.flush()
            end=time.monotonic()+args.duration
            while time.monotonic()<end:
                line=port.readline()
                if not line:continue
                text=line.decode('utf-8',errors='replace').rstrip('\r\n')
                out=f'[{now()}] {text}\n'
                f.write(out);f.flush();print(out,end='')
            if args.start_live:
                port.write(b'x');port.flush()
            print(f'LOG_SAVED: {output}')
    except (OSError,serial.SerialException) as exc:
        sys.exit(f'SERIAL_OPEN_OR_READ_FAILED: {exc}; close Vitis/other COM terminals, verify port and retry')
if __name__=='__main__':main()
