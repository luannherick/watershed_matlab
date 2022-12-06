% Open file with windows explorer
[filename, path] = uigetfile({'*.jpg';'*.png';'*.jpeg'}, "Open file");
baseFileName = [path, filename];

folder = fileparts(which(baseFileName)); 
fullFileName = fullfile(folder, baseFileName);

%% Validate the file just in case
if ~exist(fullFileName, 'file')
	% It doesn't exist in the current folder.
	% Look on the search path.
	if ~exist(baseFileName, 'file')
		% It doesn't exist on the search path either.
		% Alert user that we can't find the image.
		warningMessage = sprintf('Error: the input image file\n%s\nwas not found.\nClick OK to exit.', fullFileName);
		uiwait(warndlg(warningMessage));
		fprintf(1, 'Finished\n');
		return;
	end
	% Found it on the search path.  Construct the file name.
	fullFileName = baseFileName; % Note: don't prepend the folder.
end

I = imread(fullFileName);

%% Create ROI to analyze image
x = 150;
y = 24;
w = 500;
h = 400;
Imcropped = imcrop(I,[x y w h]);
I = Imcropped;
%figure();
%imshow(I,[]);

%% A GUI so the user can choose to convert image
[rows, columns, numberOfColorChannels] = size(I);
if numberOfColorChannels > 1
	promptMessage = sprintf(['Your image file has %d color channels.\n' ...
        'This app was designed for grayscale images.\n' ...
        'Do you want to convert it to grayscale for you so you can continue?'], numberOfColorChannels);
	button = questdlg(promptMessage, 'Continue', 'Convert and Continue', 'Cancel', 'Convert and Continue');
	if strcmp(button, 'Cancel')
		fprintf(1, 'Finished running.\n');
		return;
	end
	% Convert image to grayscale
	I = rgb2gray(I);
end

%% Contrast adjustment
I = imadjust(I, [0.52 0.72], []);
%Iadj = I;
%figure();
%imshow(Iadj, []);

binImg = imbinarize(I, 'adaptive', 'ForegroundPolarity', 'bright');
%imshow(binImg);

binImg = imfill(binImg, 'holes');

%% Remove extreme pixel values 
bot = double(prctile(binImg(:),1));
top = double(prctile(binImg(:),99));
binImg = (double(binImg) - bot) / (top - bot);
binImg(binImg > 1) = 1; 
binImg(binImg < 0) = 0; 


%% Create mask
% Threshold
I_thresh = binImg > graythresh(I); 

%   Clearing large objects bwareaopen(BW, P) 
%   P => Pixels
%   Default values with good results: 25
I_mask = bwareaopen(bwareaopen(I_thresh, 500) - binImg, 25);
%   Clear small objects
%   Default values with good results: 40
I_mask = bwareaopen(I_mask, 40);
figure();
imshow(I_mask, []);

%%  Find regional maxima
I_smooth = imgaussfilt(binImg, 2);
rmax = imregionalmax(I_smooth);
rmax(I_mask == 0) = 0; 

%% Watershed
I_min = imimposemin(max(I_smooth(:)) - I_smooth, rmax);
figure();
imshow(I_min, []);
wsImg = watershed(I_min);
wsImg(I_mask == 0) = 0; 

% Clear the border
wsImg = imclearborder(wsImg);
figure();
imshow(wsImg, []);

%% Check if it's really needed
wsImg = imfill(wsImg, 'holes');

props = regionprops(wsImg, 'all');

nBlobs = numel(props);

%% Debug to compare with the Specialist System
% Number of blobs found
%fprintf("%d blobs\n", nBlobs);

boundaries = bwboundaries(bwareaopen(bwareaopen(I_thresh, 500) - binImg, 50));

numberOfBoundaries = size(boundaries, 1);

%{
%% Debug - Mark with circles all the blobs "found"
figure('name','I','NumberTitle', 'off')
imshow(I,[]);
for k=1:length(props)
  bb = props(k).BoundingBox;
  rectangle('Position', [bb(1), bb(2), bb(3), bb(4)],...
  'EdgeColor','r','LineWidth', 0.1, 'Curvature', [1 1] )
end
%}

% Define the value of mm per pixel
mmpixel = 1;

% Virtual Sieve
diamClass = [0, 5, 8, 10, 12.5, 16, 18, 20];
sumArea = zeros(1, length(diamClass));
countedBlobs = zeros(1, length(diamClass));
avgDiamSize = zeros(1, length(diamClass));
circularities = zeros(1, length(nBlobs));

for k = 1 : nBlobs        
    for j = 1 : length(diamClass)
        blobArea = props(k).Area;	
        circularities(k) = props(k).Circularity;
        diameter = (sqrt(4*blobArea/pi)) * mmpixel;
        if j < length(diamClass) 
            if (diameter >= diamClass(j) && diameter < diamClass(j+1))...
                    && (circularities(k) > 0.5)
                countedBlobs(j) = countedBlobs(j) + 1;
                sumArea(j) = sumArea(j) + blobArea;
            end
        end
    end
end

% Passing at @ mm
passing = zeros(1, length(diamClass));
allCounted = sum(countedBlobs);

for k = 1:length(diamClass)
    avgSize = (sumArea(k) / countedBlobs(k));
    avgDiamSize(k) = (sqrt(4*avgSize/pi)) * mmpixel;
    % Debug
    % printf("Average Diam. Size (%.2f mm) = %.2f\n", diamClass(k), avgDiamSize(k));
    if k > 1
        passing(k) = round(passing(k-1) + 100 * (countedBlobs(k) / allCounted), 2);
    else
        passing(k) = round(100 * (countedBlobs(k) / allCounted), 2);
    end
    if k < length(diamClass)
        fprintf("Passing @ %.2f mm = %.2f\n", diamClass(k+1), passing(k));
    end
end

%% Color overlay 
% Display original image
% imshow(imoverlay(uint8(binImg*255),bwperim(wsImg),'r'),[]);
figure();
imshow(imoverlay(I, bwperim(wsImg)),[]);
hold on
% Display color overlay
wsImg_rgb = label2rgb(wsImg, 'jet', [1 1 1], 'shuffle');
himage = imshow(wsImg_rgb,[]);
himage.AlphaData = I_mask*.3;
% Display red borders
%[xm,ym]=find(rmax);
%hold on
%plot(ym,xm,'or','markersize',2,'markerfacecolor','g','markeredgecolor','g')