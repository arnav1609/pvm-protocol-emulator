# PC host for the FPGA demos

Use Python 3 with pySerial and the Arty programming USB cable. Select the onboard UART COM port after programming the FPGA bitstream. The bridge uses 115200 baud, 8N1 and no flow control.

From the FPGA overlay:

```powershell
python -m pip install pyserial
python host/run_demos.py --port COM5 --arm --output results/readback.jsonl
```

The program resets PVM once, then loads UART, SPI, I²C and DMX512. It reloads the same DMX512 image for the second run. `--arm` pauses after each image reaches READY so the capture can be armed before ENABLE. Use `--demo` to select one demo and `--handoff` if the Arnav handoff ZIP is elsewhere. The output path must be new.

`READBACK PASS` means the archived READY, DONE, fault code and PC, FIFO, flags, image identity and monitor values matched. The recorded fault timestamp can vary. Use the pin capture comparison for waveform acceptance. If the bridge transaction fails partway, reset the board and reopen the serial port before running again.

The host sends one SPI exchange as `01 count_hi count_lo bytes...` with a 1–260 byte payload. The bridge returns `00` followed by one MISO byte per transmitted byte. Reset is `02` and returns `00`. A malformed request returns `FF`. The loader and wire modules were copied from the handoff ZIP byte for byte.
