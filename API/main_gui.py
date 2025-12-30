# Author: 152120221098 Emre AVCI
import time
import tkinter as tk
from tkinter import messagebox

from air_conditioner import AirConditionerControlSystemConnection
from curtain_control import CurtainControlSystemConnection
from protocol import (
    GET_DESIRED_TEMPERATURE_HIGH,
    GET_DESIRED_TEMPERATURE_LOW,
    GET_AMBIENT_TEMPERATURE_HIGH,
    GET_AMBIENT_TEMPERATURE_LOW,
    GET_FAN_SPEED,
    GET_DESIRED_CURTAIN_HIGH,
    GET_DESIRED_CURTAIN_LOW,
    GET_OUTDOOR_TEMPERATURE_HIGH,
    GET_OUTDOOR_TEMPERATURE_LOW,
    GET_OUTDOOR_PRESSURE_HIGH,
    GET_OUTDOOR_PRESSURE_LOW,
    GET_LIGHT_INTENSITY_HIGH,
    GET_LIGHT_INTENSITY_LOW,
)

# ================= APP ROOT =================
root = tk.Tk()
root.title("Home Automation System")
root.geometry("1300x800")
root.configure(bg="#f1f5f9")

# ================= UI CONFIG =================
FONT_TITLE = ("Segoe UI", 22, "bold")
FONT_SUB = ("Segoe UI", 15, "bold")
FONT = ("Segoe UI", 13)

BG = "#f1f5f9"
CARD = "#ffffff"
BORDER = "#cbd5e1"
BTN = "#e2e8f0"
BTN_HOVER = "#c7d2fe"
ACCENT = "#2563eb"
TEXT = "#0f172a"
TEXT_SUB = "#475569"

# ================= APP STATE =================
selected_system = None
active_screen = "menu"  # menu / status / input

ac_conn = None
cur_conn = None

# ================= CONNECTION PARAMS =================
# The PC app opens a COM port (e.g., COM8).
# PICSimLab should open the paired port (e.g., COM9) depending on your virtual COM pair.
ac_com_var = tk.StringVar(value="COM8")
ac_baud_var = tk.StringVar(value="9600")

cur_com_var = tk.StringVar(value="COM8")
cur_baud_var = tk.StringVar(value="9600")

# ================= UI TEXT VARIABLES =================
status_label_var = tk.StringVar(value="")
conn_status_var = tk.StringVar(value="Not connected")

# ================= UART POLLING (NO THREADS) =================
POLL_INTERVAL_MS = 40   # UI-safe polling interval
RESP_TIMEOUT_MS = 150   # per-command response timeout

_poll_job = None
_pending = None  # (cmd:int, sent_at:float)
_queue = []


def _stop_polling():
    """Stop the scheduled polling loop and clear pending state."""
    global _poll_job, _pending, _queue
    if _poll_job is not None:
        try:
            root.after_cancel(_poll_job)
        except Exception:
            pass
    _poll_job = None
    _pending = None
    _queue = []


def _kick_poll_cycle():
    """Reset the request cycle so a new round of GET commands can start."""
    global _pending, _queue
    _pending = None
    _queue = []


def _build_queue() -> list[int]:
    """Return the list of GET commands for the currently selected system."""
    if selected_system == "Air Conditioner":
        return [
            GET_DESIRED_TEMPERATURE_HIGH,
            GET_DESIRED_TEMPERATURE_LOW,
            GET_AMBIENT_TEMPERATURE_HIGH,
            GET_AMBIENT_TEMPERATURE_LOW,
            GET_FAN_SPEED,
        ]
    else:
        return [
            GET_DESIRED_CURTAIN_HIGH,
            GET_DESIRED_CURTAIN_LOW,
            GET_OUTDOOR_TEMPERATURE_HIGH,
            GET_OUTDOOR_TEMPERATURE_LOW,
            GET_OUTDOOR_PRESSURE_HIGH,
            GET_OUTDOOR_PRESSURE_LOW,
            GET_LIGHT_INTENSITY_HIGH,
            GET_LIGHT_INTENSITY_LOW,
        ]


# ================= MAIN LAYOUT =================
main = tk.Frame(root, bg=BG)
main.pack(expand=True, fill="both", padx=40, pady=40)

content = tk.Frame(main, bg=BG)
content.pack(expand=True, fill="both")


# ================= UI HELPERS =================
def clear():
    """Clear current screen widgets and stop polling when leaving a screen."""
    _stop_polling()
    for w in content.winfo_children():
        w.destroy()


def card():
    """Create a styled container frame."""
    return tk.Frame(
        content,
        bg=CARD,
        highlightbackground=BORDER,
        highlightthickness=1,
        padx=40,
        pady=30,
    )


def button(parent, text, cmd):
    """Create a full-width button with fixed height and hover effect."""
    BTN_HEIGHT_PX = 54

    holder = tk.Frame(parent, bg=parent.cget("bg"), height=BTN_HEIGHT_PX)
    holder.pack(fill="x", pady=10)
    holder.pack_propagate(False)

    btn = tk.Button(
        holder,
        text=text,
        font=FONT,
        bg=BTN,
        fg=TEXT,
        relief="flat",
        padx=20,
        command=cmd,
        anchor="w",
        wraplength=0,
    )
    btn.pack(fill="both", expand=True)

    btn.bind("<Enter>", lambda e: btn.config(bg=BTN_HOVER))
    btn.bind("<Leave>", lambda e: btn.config(bg=BTN))
    return btn


def validate_float(new_value):
    """Allow empty input or any value that can be parsed as float."""
    if new_value == "":
        return True
    try:
        float(new_value)
        return True
    except ValueError:
        return False


def validate_int(new_value):
    """Allow empty input or digits only."""
    if new_value == "":
        return True
    return new_value.isdigit()


# ================= CONNECTION HELPERS =================
def _get_conn_and_params():
    """Return (conn, com_str, baud_int) for the current selected system."""
    global ac_conn, cur_conn

    if selected_system == "Air Conditioner":
        com = ac_com_var.get().strip()
        baud_s = ac_baud_var.get().strip()
        baud = int(baud_s) if baud_s.isdigit() else 9600
        return ac_conn, com, baud
    else:
        com = cur_com_var.get().strip()
        baud_s = cur_baud_var.get().strip()
        baud = int(baud_s) if baud_s.isdigit() else 9600
        return cur_conn, com, baud


def _set_conn(new_conn):
    """Store the connection object for the selected system."""
    global ac_conn, cur_conn
    if selected_system == "Air Conditioner":
        ac_conn = new_conn
    else:
        cur_conn = new_conn


def ensure_connection_object():
    """
    Create (or recreate) the connection object if needed.
    If COM/baud settings changed, closes the old connection and rebuilds it.
    """
    conn, com, baud = _get_conn_and_params()

    if conn is None:
        if selected_system == "Air Conditioner":
            conn = AirConditionerControlSystemConnection(com, baud)
        else:
            conn = CurtainControlSystemConnection(com, baud)
        _set_conn(conn)
        return conn

    try:
        curr_com = getattr(conn, "_comPort", None)
        curr_baud = getattr(conn, "_baudRate", None)
        if (curr_com != com) or (curr_baud != baud):
            try:
                conn.close()
            except Exception:
                pass

            if selected_system == "Air Conditioner":
                conn = AirConditionerControlSystemConnection(com, baud)
            else:
                conn = CurtainControlSystemConnection(com, baud)
            _set_conn(conn)
    except Exception:
        if selected_system == "Air Conditioner":
            conn = AirConditionerControlSystemConnection(com, baud)
        else:
            conn = CurtainControlSystemConnection(com, baud)
        _set_conn(conn)

    return conn


def _is_open(conn) -> bool:
    """Return True if the connection is open and UART backend exists."""
    return bool(getattr(conn, "_isOpen", False)) and (getattr(conn, "_uart", None) is not None)


def connect_selected():
    """Open UART connection for the currently selected system."""
    conn = ensure_connection_object()

    if _is_open(conn):
        messagebox.showinfo("Connection", "Already connected")
        return

    ok = False
    try:
        ok = conn.open()
    except Exception as e:
        messagebox.showerror("UART Error", f"Open failed:\n{e}")
        ok = False

    conn_status_var.set("Connected" if ok else "Not connected")
    _kick_poll_cycle()
    _start_polling()
    _update_status_text_from_cache()


def disconnect_selected():
    """Close UART connection for the currently selected system."""
    conn = ensure_connection_object()
    try:
        conn.close()
    except Exception:
        pass
    conn_status_var.set("Not connected")
    _stop_polling()
    _update_status_text_from_cache()


# ================= STATUS DISPLAY =================
def _update_status_text_from_cache():
    """
    Update the status label from cached values inside the connection object.
    This function does not block and does not perform UART reads/writes.
    """
    conn = ensure_connection_object()
    is_open = _is_open(conn)
    conn_status_var.set("Connected" if is_open else "Not connected")

    _, com, baud = _get_conn_and_params()

    if selected_system == "Air Conditioner":
        desired = conn.peekDesiredTemp() if is_open else "N/A"
        ambient = conn.peekAmbientTemp() if is_open else "N/A"
        fan = conn.peekFanSpeed() if is_open else "N/A"

        status_text = (
            f"Home Ambient Temperature : {ambient} °C\n"
            f"Home Desired Temperature : {desired} °C\n"
            f"Fan Speed                : {fan} rps\n"
            f"------------------------------------------\n"
            f"Connection Status         : {conn_status_var.get()}\n"
            f"PC Port (this app)        : {com}\n"
            f"PICSim paired port        : COM9 (example)\n"
            f"Connection Baudrate       : {baud}"
        )
    else:
        out_t = conn.peekOutdoorTemp() if is_open else "N/A"
        out_p = conn.peekOutdoorPress() if is_open else "N/A"
        cur_s = conn.peekCurtainStatus() if is_open else "N/A"
        light = conn.peekLightIntensity() if is_open else "N/A"

        status_text = (
            f"Outdoor Temperature      : {out_t} °C\n"
            f"Outdoor Pressure         : {out_p}\n"
            f"Curtain Status           : {cur_s} %\n"
            f"Light Intensity          : {light}\n"
            f"------------------------------------------\n"
            f"Connection Status         : {conn_status_var.get()}\n"
            f"PC Port (this app)        : {com}\n"
            f"PICSim paired port        : COM9 (example)\n"
            f"Connection Baudrate       : {baud}"
        )

    status_label_var.set(status_text)


# ================= POLLING LOOP =================
def _start_polling():
    """Start the Tkinter after() polling loop if it is not running."""
    global _poll_job
    if _poll_job is None:
        _poll_job = root.after(POLL_INTERVAL_MS, _poll_tick)


def _poll_tick():
    """
    Non-blocking UART polling using Tkinter's after() scheduler.
    Sends one request at a time and reads at most one response byte per tick.
    """
    global _poll_job, _pending, _queue

    if active_screen != "status":
        _stop_polling()
        return

    conn = ensure_connection_object()
    if not _is_open(conn):
        _update_status_text_from_cache()
        _poll_job = root.after(POLL_INTERVAL_MS, _poll_tick)
        return

    # 1) If waiting for a response, attempt a non-blocking read
    if _pending is not None:
        cmd, sent_at = _pending
        b = conn._uart_read_byte_now()
        if b is not None:
            try:
                conn.handle_rx(cmd, b)
            except Exception:
                pass
            _pending = None
        else:
            if (time.monotonic() - sent_at) * 1000.0 > RESP_TIMEOUT_MS:
                # Timeout: flush input to avoid stale bytes and move on
                try:
                    conn._uart_flush_input()
                except Exception:
                    pass
                _pending = None

    # 2) If no pending request, send the next GET command
    if _pending is None:
        if not _queue:
            _queue = _build_queue()

        if _queue:
            cmd = _queue.pop(0)
            try:
                ok = conn._uart_write_byte(cmd)
            except Exception:
                ok = False

            if ok:
                _pending = (cmd, time.monotonic())

                # Optional immediate read (sometimes response arrives quickly)
                b = conn._uart_read_byte_now()
                if b is not None:
                    try:
                        conn.handle_rx(cmd, b)
                    except Exception:
                        pass
                    _pending = None

    # 3) Refresh UI from cached values
    _update_status_text_from_cache()

    # 4) Schedule next poll tick
    _poll_job = root.after(POLL_INTERVAL_MS, _poll_tick)


def refresh_status():
    """Refresh button handler: restart the request cycle without blocking the UI."""
    _kick_poll_cycle()
    _update_status_text_from_cache()

    if active_screen == "status" and _poll_job is None:
        _start_polling()


# ================= SCREEN 1: MAIN MENU =================
def main_menu():
    global active_screen
    active_screen = "menu"
    clear()

    box = card()
    box.pack(fill="x")

    tk.Label(
        box,
        text="MAIN MENU",
        font=FONT_TITLE,
        bg=CARD,
        fg=ACCENT,
    ).pack(pady=(0, 30))

    button(box, "1. Air Conditioner", lambda: select_system("Air Conditioner"))
    button(box, "2. Curtain Control", lambda: select_system("Curtain Control"))
    button(box, "3. Exit", on_exit)


def select_system(system_name):
    """Select a subsystem and open its status screen."""
    global selected_system
    selected_system = system_name
    status_screen()


# ================= SCREEN 2: STATUS =================
def status_screen():
    global active_screen
    active_screen = "status"

    clear()
    box = card()
    box.pack(fill="x")

    tk.Label(
        box,
        text=f"Selected System: {selected_system}",
        font=FONT_TITLE,
        bg=CARD,
        fg=ACCENT,
    ).pack(anchor="w", pady=(0, 20))

    # Connection settings
    settings = tk.Frame(box, bg=CARD)
    settings.pack(fill="x", pady=(0, 15))

    tk.Label(settings, text="COM Port (PC):", font=FONT, bg=CARD, fg=TEXT_SUB).grid(row=0, column=0, sticky="w")
    tk.Label(settings, text="Baudrate:", font=FONT, bg=CARD, fg=TEXT_SUB).grid(row=0, column=2, sticky="w", padx=(20, 0))

    if selected_system == "Air Conditioner":
        com_var = ac_com_var
        baud_var = ac_baud_var
    else:
        com_var = cur_com_var
        baud_var = cur_baud_var

    com_entry = tk.Entry(settings, font=FONT, relief="solid", bd=1, textvariable=com_var)
    com_entry.grid(row=0, column=1, sticky="we", padx=(10, 0))

    baud_entry = tk.Entry(
        settings,
        font=FONT,
        relief="solid",
        bd=1,
        textvariable=baud_var,
        validate="key",
        validatecommand=(root.register(validate_int), "%P"),
    )
    baud_entry.grid(row=0, column=3, sticky="we", padx=(10, 0))

    settings.grid_columnconfigure(1, weight=1)
    settings.grid_columnconfigure(3, weight=1)

    tk.Label(
        box,
        text="Note: This app opens COM8. On the PICSimLab side, you must use the paired port (e.g., COM9).",
        font=("Segoe UI", 11),
        bg=CARD,
        fg=TEXT_SUB,
    ).pack(anchor="w", pady=(0, 10))

    # Connection controls
    btn_row = tk.Frame(box, bg=CARD)
    btn_row.pack(fill="x", pady=(0, 10))

    tk.Button(btn_row, text="Connect", font=FONT, bg=BTN, relief="flat", command=connect_selected).pack(side="left", padx=(0, 10))
    tk.Button(btn_row, text="Disconnect", font=FONT, bg=BTN, relief="flat", command=disconnect_selected).pack(side="left", padx=(0, 10))
    tk.Button(btn_row, text="Refresh", font=FONT, bg=BTN, relief="flat", command=refresh_status).pack(side="left")

    tk.Label(
        box,
        textvariable=status_label_var,
        font=FONT,
        bg=CARD,
        fg=TEXT_SUB,
        justify="left",
    ).pack(anchor="w", pady=(10, 0))

    tk.Label(
        box,
        text="\nMENU",
        font=FONT_SUB,
        bg=CARD,
        fg=ACCENT,
    ).pack(pady=(30, 15))

    action_text = "Enter the desired temperature" if selected_system == "Air Conditioner" else "Enter the desired curtain status"
    button(box, f"1. {action_text}", input_screen)
    button(box, "2. Return", main_menu)

    _kick_poll_cycle()
    _start_polling()
    _update_status_text_from_cache()


# ================= SCREEN 3: INPUT =================
def input_screen():
    global active_screen
    active_screen = "input"

    clear()
    box = card()
    box.pack(fill="x")

    action = "Enter Desired Temperature" if selected_system == "Air Conditioner" else "Enter Desired Curtain Status"

    tk.Label(
        box,
        text=f"Selected System: {selected_system}",
        font=FONT_TITLE,
        bg=CARD,
        fg=ACCENT,
    ).pack(anchor="w", pady=(0, 10))

    tk.Label(
        box,
        text=f"Action: {action}",
        font=FONT_SUB,
        bg=CARD,
        fg=TEXT,
    ).pack(anchor="w", pady=(0, 25))

    tk.Label(
        box,
        text=action + ":",
        font=FONT,
        bg=CARD,
        fg=TEXT_SUB,
    ).pack(anchor="w")

    value_var = tk.StringVar()

    entry = tk.Entry(
        box,
        font=FONT,
        relief="solid",
        bd=1,
        textvariable=value_var,
        validate="key",
        validatecommand=(root.register(validate_float), "%P"),
    )
    entry.pack(fill="x", pady=15)
    entry.focus_set()

    def send_value():
        """
        Send a SET value to the PIC.
        Polling is temporarily stopped to avoid collision with GET polling traffic.
        """
        global _poll_job, _pending, _queue
        conn = ensure_connection_object()

        # Stop polling while sending a SET command
        if _poll_job is not None:
            try:
                root.after_cancel(_poll_job)
            except Exception:
                pass
            _poll_job = None

        _pending = None
        _queue = []

        if not _is_open(conn):
            messagebox.showerror("Error", "Connection is not open!")
            _start_polling()
            return

        txt = value_var.get().strip()
        if not txt:
            _start_polling()
            return

        try:
            val = float(txt)

            if selected_system == "Air Conditioner":
                ok = conn.setDesiredTemp(val)
            else:
                ok = conn.setCurtainStatus(val)

            if ok:
                messagebox.showinfo("Success", f"Value ({val}) has been sent.")
                status_screen()
            else:
                messagebox.showerror("Error", "PIC did not receive the data packet.")
                status_screen()

        except Exception as e:
            messagebox.showerror("Error", f"Numeric input error or UART error: {e}")
            status_screen()

        # Restart polling after the status screen is rebuilt
        root.after(200, _start_polling)

    button(box, "1. Enter (Send)", send_value)
    button(box, "2. Return", status_screen)


# ================= APP CLOSE =================
def on_exit():
    """Close UART connections and exit the app cleanly."""
    global ac_conn, cur_conn
    _stop_polling()

    try:
        if ac_conn is not None:
            ac_conn.close()
    except Exception:
        pass

    try:
        if cur_conn is not None:
            cur_conn.close()
    except Exception:
        pass

    root.destroy()


root.protocol("WM_DELETE_WINDOW", on_exit)

# ================= START =================
main_menu()
root.mainloop()
