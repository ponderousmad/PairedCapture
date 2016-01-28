# PairedCapture
Experimental image and depth frame capture from Structure Sensor.

Basically takes the image captured from the camera, and the depth information from the sensor and fuses it into a single image.

14 bits of depth is encoded into quasi-greyscale. This allows for 15 meters of per-millimeter accuracy.

A 'save' button writes this image to the device's photo library as png (since jpg would break the encoding).

An example of how to extract the depth portion of the image and decode it can be found in [pydent](https://github.com/ponderousmad/pyndent/blob/master/explore/decode.ipynb).
